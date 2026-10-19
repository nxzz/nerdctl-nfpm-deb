# nerdctl-deb

[nerdctl](https://github.com/containerd/nerdctl) の full 版リリース (`nerdctl-full-*-linux-*.tar.gz`) を、[nfpm](https://nfpm.goreleaser.com/) を使って Ubuntu 向けの `.deb` に詰め直すスクリプトです。

full 版に含まれる containerd / runc / BuildKit / CNI プラグインなどをまとめて `/opt/nerdctl` 以下に置き、システム側へのシンボリックリンクは最小限にとどめます。

## ビルド

必要なもの: `bash`, `curl`, `tar`, `sha256sum`, `sed`, [`nfpm`](https://nfpm.goreleaser.com/install/)

```sh
./build.sh                # 最新版 / amd64
./build.sh 2.4.1          # バージョン指定
./build.sh 2.4.1 arm64    # バージョン + アーキテクチャ指定 (amd64 | arm64)
```

成果物は `./dist/nerdctl-full_<VERSION>-1_<ARCH>.deb` に出力されます (`OUT_DIR` 環境変数で変更可)。

`build.sh` は次の処理を行います。

1. GitHub Releases から tarball と `SHA256SUMS` を取得し、ハッシュを検証
2. 一時ディレクトリに `/opt/nerdctl` として展開
3. 同梱の systemd ユニットのパスを `/usr/local/bin` → `/opt/nerdctl/bin` に書き換え、`PATH` を追加
4. `nfpm package` で `.deb` を生成

> **Note**
> 実行ビットを保つため Linux 上で実行してください。Windows の場合は WSL から実行できます (一時ファイルは Linux 側の `/tmp` に作られるので、リポジトリが `/mnt/...` にあっても問題ありません)。

## インストール

```sh
sudo apt install ./dist/nerdctl-full_2.4.1-1_amd64.deb
```

初回インストール時に `containerd.service` と `buildkit.service` が有効化・起動されます。

```sh
sudo nerdctl run --rm hello-world
```

## インストールされるもの

| パス | 内容 |
| --- | --- |
| `/opt/nerdctl/` | tarball の中身 (`bin/`, `libexec/cni/`, `share/`) |
| `/usr/bin/nerdctl` | → `/opt/nerdctl/bin/nerdctl` |
| `/usr/bin/buildctl` | → `/opt/nerdctl/bin/buildctl` (`nerdctl build` が PATH から探すため) |
| `/usr/bin/ctr` | → `/opt/nerdctl/bin/ctr` (containerd のデバッグ用) |
| `/usr/lib/systemd/system/containerd.service` | containerd |
| `/usr/lib/systemd/system/buildkit.service` | BuildKit |
| `/usr/lib/systemd/system/stargz-snapshotter.service` | stargz snapshotter (既定では無効) |
| `/etc/nerdctl/nerdctl.toml` | `cni_path = "/opt/nerdctl/libexec/cni"` (conffile) |

shim や runc はシンボリックリンクを張らず、systemd ユニットの `Environment=PATH=...` で `/opt/nerdctl/bin` を見せています。

## 注意事項

- `containerd`, `containerd.io`, `docker.io`, `docker-ce` パッケージとは `Conflicts` 指定しています (`containerd.service` が衝突するため)。
- `nerdctl run --init` は `tini` を PATH から探すため、使う場合は `sudo ln -s /opt/nerdctl/bin/tini /usr/local/bin/tini` などで対応してください。
- rootless モードは自動ではセットアップされません。下記「rootless モード」を参照してください。

## rootless モード

一般ユーザー権限で containerd / BuildKit を動かす場合の手順です。
ユーザー単位の systemd サービスとして動かすので、**ssh や GUI で対象ユーザーとして直接ログインして**作業してください (`sudo su - user` では systemd のユーザーセッションが無いため失敗します)。

### 1. 前提パッケージとサブ UID/GID (root)

```sh
sudo apt install uidmap dbus-user-session
```

対象ユーザーに subuid / subgid が割り当てられていることを確認します。通常は `adduser` で作成したユーザーなら設定済みです。

```sh
grep "^$(id -un):" /etc/subuid /etc/subgid
# 何も出なければ追加:
# sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 <user>
```

### 2. AppArmor プロファイル (Ubuntu 24.04 以降のみ, root)

Ubuntu 24.04 以降は非特権ユーザー名前空間が AppArmor で制限されているため、`/opt/nerdctl/bin/rootlesskit` 用のプロファイルが必要です ([参考](https://rootlesscontaine.rs/getting-started/common/apparmor/))。

```sh
sudo tee /etc/apparmor.d/opt.nerdctl.bin.rootlesskit <<'EOF'
abi <abi/4.0>,
include <tunables/global>

"/opt/nerdctl/bin/rootlesskit" flags=(unconfined) {
  userns,

  include if exists <local/opt.nerdctl.bin.rootlesskit>
}
EOF
sudo systemctl restart apparmor.service
```

### 3. containerd / BuildKit のセットアップ (一般ユーザー)

`containerd-rootless-setuptool.sh` は自分自身の場所を PATH から探し、そのディレクトリを systemd ユーザーユニットの `PATH` に書き込みます。そのため **`/opt/nerdctl/bin` を PATH に入れて実行**してください。

```sh
export PATH=/opt/nerdctl/bin:$PATH

containerd-rootless-setuptool.sh check
containerd-rootless-setuptool.sh install            # containerd (rootless)
containerd-rootless-setuptool.sh install-buildkit   # BuildKit (nerdctl build 用)
```

`~/.config/systemd/user/` にユニットが作られ、起動まで行われます。

### 4. nerdctl の設定 (一般ユーザー)

rootless 時の nerdctl は `/etc/nerdctl/nerdctl.toml` ではなく `~/.config/nerdctl/nerdctl.toml` を読むため、CNI プラグインの場所をここでも指定します。

```sh
mkdir -p ~/.config/nerdctl
cat > ~/.config/nerdctl/nerdctl.toml <<'EOF'
cni_path = "/opt/nerdctl/libexec/cni"
EOF
```

### 5. 動作確認

```sh
nerdctl run --rm hello-world
nerdctl info | grep -i rootless
```

### 任意の設定

- ログアウト後や OS 起動時にも動かし続ける:

  ```sh
  sudo loginctl enable-linger $(id -un)
  ```

- rootful の containerd / BuildKit が不要なら止めておく:

  ```sh
  sudo systemctl disable --now containerd.service buildkit.service
  ```

### rootless モードの解除

```sh
export PATH=/opt/nerdctl/bin:$PATH
containerd-rootless-setuptool.sh uninstall-buildkit
containerd-rootless-setuptool.sh uninstall
rootlesskit rm -rf ~/.local/share/containerd ~/.local/share/buildkit   # データも消す場合
```

## ファイル構成

```
.
├── build.sh                    # ダウンロード〜deb 生成
├── nfpm.yaml                   # パッケージ定義
└── packaging/
    ├── nerdctl.toml            # /etc/nerdctl/nerdctl.toml
    └── scripts/                # postinstall / preremove / postremove
```
