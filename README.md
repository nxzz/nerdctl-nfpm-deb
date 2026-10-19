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
- rootless モードで使う場合は、`/opt/nerdctl/bin` を PATH に含めた上でセットアップしてください。

  ```sh
  export PATH=/opt/nerdctl/bin:$PATH
  containerd-rootless-setuptool.sh install
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
