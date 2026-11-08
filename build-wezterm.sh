#!/bin/zsh
# Build the pinned WezTerm plus mouse tab dragging. --install also replaces the app.
set -euo pipefail
repo=${0:A:h}
[[ $# == 0 || ( $# == 1 && $1 == --install ) ]] || { print -u2 'Usage: ./build-wezterm.sh [--install]'; exit 2 }
install_app=${1-}
upstream=e68a8ec27727fbbda15e07f0a0737cd5e16481f6
build=$repo/.build
patch_id=$(shasum -a 256 "$repo/patches/tab-drag.patch" | cut -d' ' -f1)
build_id=$(cat "$repo/build-wezterm.sh" "$repo/patches/tab-drag.patch" | shasum -a 256 | cut -d' ' -f1)
stamp="$upstream-$build_id-$(uname -m)"
source_dir=$build/source-${upstream[1,8]}-${patch_id[1,12]}
built_app=$build/WezTerm.app
marker=Contents/Resources/warpstyle-build
app=/Applications/WezTerm.app

if [[ ! -r $built_app/$marker || $(<$built_app/$marker) != $stamp ]]; then
  for tool in git cargo rustc cmake pkg-config; do
    command -v "$tool" >/dev/null || { print -u2 "Missing $tool. Run ./install.sh first."; exit 1 }
  done
  xcrun --show-sdk-path >/dev/null
  openssl_dir=$(brew --prefix openssl@3)
  mkdir -p "$source_dir"
  if [[ ! -d $source_dir/.git ]]; then
    git -C "$source_dir" init -q
    git -C "$source_dir" remote add origin https://github.com/wezterm/wezterm.git
  fi
  if ! git -C "$source_dir" cat-file -e "$upstream^{commit}" 2>/dev/null; then
    git -C "$source_dir" fetch --depth=1 origin "$upstream"
  fi
  if [[ ! -f $source_dir/.warpstyle-patched ]]; then
    git -C "$source_dir" checkout --detach "$upstream"
    git -C "$source_dir" submodule update --init --recursive --depth=1
    git -C "$source_dir" apply --check "$repo/patches/tab-drag.patch"
    git -C "$source_dir" apply "$repo/patches/tab-drag.patch"
    touch "$source_dir/.warpstyle-patched"
  fi
  (
    cd "$source_dir"
    export CARGO_TARGET_DIR=$build/target OPENSSL_DIR=$openssl_dir OPENSSL_STATIC=1 LIBGIT2_NO_PKG_CONFIG=1
    print -r -- '20261026-082628-e68a8ec2-warpstyle-tab-drag' > .tag
    cargo test --locked --release -p mux --lib tab_drag_detach -- --test-threads=1
    cargo test --locked --release -p wezterm-gui --bin wezterm-gui tab_drag
    cargo build --locked --release -p wezterm-gui -p wezterm -p wezterm-mux-server -p strip-ansi-escapes
  )

  package=$(mktemp -d "$build/package.XXXXXX")
  trap 'rm -rf "$package"' EXIT
  /usr/bin/ditto "$source_dir/assets/macos/WezTerm.app" "$package/WezTerm.app"
  rm -f "$package/WezTerm.app/"*.dylib(N)
  resources=$package/WezTerm.app/Contents/Resources
  mkdir -p "$package/WezTerm.app/Contents/MacOS"
  for binary in wezterm wezterm-gui wezterm-mux-server strip-ansi-escapes; do
    cp "$build/target/release/$binary" "$package/WezTerm.app/Contents/MacOS/$binary"
    if otool -L "$package/WezTerm.app/Contents/MacOS/$binary" | grep -E '^[[:space:]]+/(opt/homebrew|usr/local)/'; then
      print -u2 "$binary still depends on a Homebrew library; refusing to install."
      exit 1
    fi
  done
  /usr/bin/ditto "$source_dir/assets/shell-integration" "$resources"
  /usr/bin/ditto "$source_dir/assets/shell-completion" "$resources/shell-completion"
  tic -xe wezterm -o "$resources/terminfo" "$source_dir/termwiz/data/wezterm.terminfo"
  print -r -- "$stamp" > "$package/WezTerm.app/$marker"
  codesign --force --sign - "$package/WezTerm.app"
  codesign --verify --deep --strict "$package/WezTerm.app"
  rm -rf "$built_app"
  mv "$package/WezTerm.app" "$built_app"
fi

# show-keys can exit successfully after rejecting a config; check our own binding too.
"$built_app/Contents/MacOS/wezterm" --version | grep -F -- '-warpstyle-tab-drag'
"$built_app/Contents/MacOS/wezterm" --config-file "$repo/wezterm.lua" show-keys > "$build/config-check.txt" 2> "$build/config-errors.txt"
grep -F 'Key Table: select_all' "$build/config-check.txt"
[[ ! -s $build/config-errors.txt ]] || { cat "$build/config-errors.txt" >&2; exit 1 }
codesign --verify --deep --strict "$built_app"
[[ $install_app == --install ]] || { print "Built $built_app"; exit 0 }

if [[ -r $app/$marker && $(<$app/$marker) == $stamp ]]; then
  print 'The custom WezTerm is already installed.'
else
  # Stage and verify everything before removing a Homebrew-managed app.
  staged=$(mktemp -d /Applications/.wezterm-install.XXXXXX)
  /usr/bin/ditto "$built_app" "$staged/WezTerm.app"
  codesign --verify --deep --strict "$staged/WezTerm.app"
  backup=$(mktemp -d "$build/backup.XXXXXX")
  if [[ -d $app ]]; then
    /usr/bin/ditto "$app" "$backup/WezTerm.app"
    print "Previous app saved to $backup/WezTerm.app"
  fi
  restore_app() {
    if [[ ! -d $app && -d $backup/WezTerm.app ]]; then
      /usr/bin/ditto "$backup/WezTerm.app" "$app"
    fi
  }
  for cask in wezterm wezterm@nightly; do
    if brew list --cask "$cask" >/dev/null 2>&1; then
      brew uninstall --cask "$cask" || { restore_app; exit 1 }
    fi
  done
  if [[ -e $app ]]; then
    mv "$app" "$backup/replaced.app"
  fi
  mv "$staged/WezTerm.app" "$app" || { restore_app; exit 1 }
  rmdir "$staged"
fi

prefix=$(brew --prefix)
mkdir -p "$prefix/bin" "$prefix/etc/bash_completion.d" "$prefix/share/zsh/site-functions" "$prefix/share/fish/vendor_completions.d"
for binary in wezterm wezterm-gui wezterm-mux-server strip-ansi-escapes; do
  ln -sfn "$app/Contents/MacOS/$binary" "$prefix/bin/$binary"
done
ln -sfn "$app/Contents/Resources/shell-completion/bash" "$prefix/etc/bash_completion.d/wezterm"
ln -sfn "$app/Contents/Resources/shell-completion/zsh" "$prefix/share/zsh/site-functions/_wezterm"
ln -sfn "$app/Contents/Resources/shell-completion/fish" "$prefix/share/fish/vendor_completions.d/wezterm.fish"
"$app/Contents/MacOS/wezterm" --version
print 'Installed. Save terminal work, press Cmd+Q to fully quit WezTerm, then reopen it.'
