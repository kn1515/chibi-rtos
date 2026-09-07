# chibi-os — Milk-V Duoから始める自作OS

初代 **Milk-V Duo（CV1800B、64MB）** のメインC906コアで動く、最小のRISC-Vカーネルです。
U-Bootの `bootm` からS-modeで起動し、自前のスタックとUARTドライバを使って次を表示します。

```text
Hello chibi-os
```

ESP-IDF・FreeRTOSに依存するスケジューラから、**独立したfreestandingカーネル**へ変更しました。
Cランタイム・標準ライブラリ・U-Bootのサービス関数を使いません。
まだプロセス、仮想記憶、ファイルシステム、システムコールはありません。
通常のOSへ育てるため、まず「ブートローダーから制御を受け取り、Cを動かす」部分を実装しています。
リポジトリ名 `chibi-rtos` はそのままです。旧ESP32版はGit履歴の
[`b76b1e4`](https://github.com/kn1515/chibi-rtos/tree/b76b1e4ec80fb2debacfc886180dafafa59512a1) に残っています。

## 対象と前提

- 初代Milk-V Duo、CV1800B、64MB、RISC-Vメインコア。**Duo 256M・Duo Sは対象外**です。
- メーカーの初代Duo用SDイメージで、U-Bootのコンソールまで正常に起動できること。
- U-Bootは公式SDKの `CONFIG_RISCV_SMODE=y`、FIT対応構成を基準にしています。
- PC：Ubuntu 24.04を手順の基準とします。Debianでも同じパッケージ名を使います。
- microSD、カードリーダー、3.3V対応USB-UART変換器、配線3本。

メーカーのBoot ROM → FSBL → OpenSBI → U-Bootを再利用します。
FSBL/U-BootがDRAM・クロック・UARTのピン設定を済ませた後にカーネルを実行します。
OpenSBIはM-modeに残ります。カーネルはS-modeで動作し、今回SBI呼び出しは行いません。
小コアの状態はメーカーのファームウェアに依存し、この実装では起動・停止・通信を行いません。

## なぜ `go` ではなく `bootm` なのか

初代Duoの公式ボード設定では `CONFIG_CMD_GO` と `CONFIG_CMD_BOOTI` が無効です。
有効なFIT形式と `bootm` を使い、U-Bootの再ビルドを不要にしました。

`make build` はカーネルのバイナリと最小Device Treeを **`chibi-os.itb`（FITイメージ）** にまとめます。
FITの `os = "linux"` は、U-BootのLinux用引き渡し規約を選ぶためのメタデータです。
Linux本体を含めるという意味ではありません。
この経路ではU-Bootが起動前処理を行い、`a0=hart ID`、`a1=DTBアドレス` を渡します。
Device Treeが必要なので、この固定ボード用の小さなDTBを同梱しています。
**このDTBはLinuxを起動するための完全なボード定義ではありません。**

## 1. セットアップとビルド

PCのターミナルで実行します。既にclone済みなら、リポジトリ内で `git pull` してから進めます。

```bash
sudo apt update
sudo apt install -y git make
git clone https://github.com/kn1515/chibi-rtos.git
cd chibi-rtos
make setup
make build
```

`make setup` はGCC/BinutilsのRISC-V bare-metalツールチェーン、`dtc`、`mkimage`、
`picocom`、Pythonを導入します。通常ユーザーで実行し、aptの操作時だけsudoを使います。
**ESP-IDFやメーカーの巨大なSDKのダウンロードは不要です。**

既に依存ツールがある場合は `make setup SKIP_DEPS=1` で存在チェックのみを実行できます。
別のGNUツールチェーンを使う場合は、各コマンドへ `CROSS_COMPILE=/path/to/riscv64-unknown-elf-`
を指定してください。ISAは `rv64imac_zicsr_zifencei`、ABIは `lp64` です。
C906固有命令や浮動小数点命令を使わない構成です。

| 生成物 | 用途 |
| --- | --- |
| `build/chibi-os.elf` | シンボル・デバッグ情報付きカーネル |
| `build/chibi-os.bin` | ヘッダーなしの機械語と初期化データ |
| `build/duo.dtb` | このカーネル用の最小Device Tree |
| **`build/chibi-os.itb`** | **SDカードへコピーする起動イメージ** |
| `build/chibi-os.map` | 関数・データ・スタックの配置 |

## 2. SDカードへコピーする

メーカーの初代Duo用イメージで起動できるSDカードを使います。初回のSDイメージ作成は
[公式の導入手順](https://milkv.io/docs/duo/getting-started/boot)に従ってください。
OSイメージを新規に書き込む操作はSDカードの内容を消します。
本リポジトリのMakefileはSDカードのフォーマットやディスク全体への書き込みを行いません。

PCでSDカードのFATブートパーティション（`fip.bin`、`boot.sd` がある場所）をマウントし、
そこへ `build/chibi-os.itb` をコピーします。Linuxの例：

```bash
make sd-copy SD_DIR=/media/yourname/boot
```

`SD_DIR` は実際のマウント先へ置き換えてください。
このコマンドはマウントポイントと `fip.bin` の存在を確認して、`chibi-os.itb` だけを書き込みます。
既に同名ファイルがあれば更新します。ファイルマネージャーでのコピーでも構いません。
コピー後は安全にアンマウントしてから抜いてください。
`fip.bin`、`boot.sd`、U-Bootの保存済み環境変数を変更する必要はありません。

## 3. UART配線

ボードはUSB-Cから給電し、USB-UART変換器は信号線とGNDだけ接続します。
**3.3Vロジック用の変換器を使い、5V信号やVCC線をDuoへ接続しないでください。**

| Milk-V Duo | 物理ピン番号 | USB-UART側 |
| --- | --- | --- |
| GP12 / UART0 TX | 16 | RX |
| GP13 / UART0 RX | 17 | TX |
| GND | 18 | GND |

TXとRXは交差させます。USB-Cケーブルだけでは、この手順のUART0コンソールは開けません。
UARTは **115200bps、8データビット、パリティなし、1ストップビット、フロー制御なし** です。
配線位置は[公式の初代Duoピン配置](https://milkv.io/docs/duo/getting-started/duo)も確認してください。

PCでシリアルポートを確認し、例えば `/dev/ttyUSB0` なら次を実行します。

```bash
make monitor PORT=/dev/ttyUSB0
```

picocomの終了は **Ctrl+A、続けてCtrl+X** です。
Linuxで権限エラーの場合は `sudo usermod -aG dialout "$USER"` の後にログアウト・再ログインします。
WindowsではTera Term等のシリアルソフトでも構いません。
WSL2では、書き込み用SDのマウントとUARTアダプターのUSB接続を別途設定するか、
ビルドだけWSL2で行い、コピーとUART操作をWindows側で行ってください。

## 4. U-Bootから起動する

SDカードをDuoへ戻し、UARTモニターを開いた状態で電源を入れます。
ブートログの `Hit any key to stop autoboot` が出たらキーを押して自動起動を止めます。
公式設定の待ち時間は短いので、電源投入前からモニターを開いてください。

`cv180x_c906#` などの **U-Bootプロンプト** で、次を1行ずつ実行します。
PCのシェルや、起動済みLinuxのシェルで実行するコマンドではありません。

```text
mmc dev 0
fatls mmc 0:1
fatload mmc 0:1 0x81400000 chibi-os.itb
bootm 0x81400000#conf-duo
```

`fatls` でファイルが見え、`fatload` が成功してバイト数を表示したことを確認してから
`bootm` を実行してください。デバイス・パーティション番号はメーカーSDの `mmc 0:1` を基準にしています。
異なる構成の場合は `mmc list` や `part list mmc 0` で確認し、実際の番号に置き換えます。
PCでは `make boot-commands` で同じコマンドを表示できます。

起動できると、U-BootのFIT読込・検証メッセージに続いて次が表示されます。
下記は想定される表示形式で、実機で取得したログではありません。

```text
Starting kernel ...

Hello chibi-os
```

表示後はカーネルのループで停止し、U-Bootへは戻りません。再試行には電源を入れ直します。
今回の手順では永続的な自動起動設定を変えないので、次の起動時には元のSD起動手順になります。
`bootm` の引数に `.bin` や `.elf` を渡す手順ではありません。必ず `.itb` をロードしてください。

## 起動後に自作コードが行うこと

1. Supervisor割り込みを止め、自前の例外停止先を `stvec` に設定する。
2. `satp=0` として物理アドレスで実行し、TLB・命令フェンスを行う。
3. `gp` と16KiBの専用スタックを設定する。
4. `.bss` をゼロクリアし、U-Bootの引数を保持したままCへ入る。
5. `.bss` と `.data` の初期状態を確認する。
6. UART0の送信可能ビットをポーリングし、32bit MMIO書き込みで文字を送る。
7. 送信完了を待ち、自前の停止ループに入る。

UARTのクロック・pinmux・ボーレートはU-Bootの初期化結果を引き継ぎます。
UART0のベースは `0x04140000`、レジスタ間隔は4バイト、LSRは `+0x14` です。
U-BootやOpenSBIの文字出力関数は呼びません。
例外発生時は `trap_entry` で停止し、`t0=scause`、`t1=sepc`、`t2=stval` をデバッガーで確認できます。

| メモリ領域 | この実装での用途 |
| --- | --- |
| `0x80000000` から | DRAM先頭。OpenSBI等の領域を使用しない |
| `0x80200000`〜`0x802fffff` | カーネル用1MiB。先頭がエントリーポイント |
| `0x81400000` から | U-BootがFITイメージを一時的にロードする位置 |
| DRAM上部 | メーカーの予約領域・小コア等を使用しない |

カーネルのメモリ上限とスタック整列はリンカのASSERTで検査します。
U-Bootの元のリンクアドレスも `0x80200000` ですが、ここではDRAM上部へのリロケーションを
完了し、コマンドを受け付けているメーカーの通常起動経路を前提にしています。
独自U-Boot、リロケーションを無効化した構成、異なるメモリマップにはそのまま適用できません。

## テストと検証範囲

```bash
make setup-test
make test
```

`setup-test` は `.venv` にテスト用のUnicornとpyelftoolsをインストールします。
`make test` は **ビルドした実際のRISC-Vバイナリ** をS-modeで実行し、UARTのMMIOだけを模擬します。
BSSを意図的に非ゼロにした状態から起動して初期化を検証し、UARTが一時的に送信不可の場合も確認します。

確認済み：

- GNU RISC-V GCC 12.2.0 / Binutils 2.40によるクロスビルド。
- dtc 1.6.1 / mkimage 2023.01によるDevice Tree・FIT生成。
- エントリー、BSS、スタック配置、未解決シンボルがないこと。
- FIT内のカーネルとDTBが生成ファイルと一致し、CRC32が一致すること。
- S-modeからの起動、`Hello chibi-os\r\n` の送信、引数保持、停止処理。
- `.data` 破損時のエラーメッセージ。

**未確認：Milk-V Duo実機での起動、実際のU-Boot/OpenSBI引き渡し、UARTの電気的動作。**
UnicornはCV1800B全体を再現するエミュレータではなく、キャッシュ、DRAM初期化、
実際のUARTのクロックや配線、PMP設定、SDカード読込は検証していません。

## ファイル構成

| ファイル | 役割 |
| --- | --- |
| `src/start.S` | S-modeエントリー、スタック、BSS、例外停止 |
| `src/kernel.c` | 初期状態確認とHelloメッセージ |
| `src/uart.c` | UART0のポーリング出力 |
| `include/platform.h` | DuoのUART定数 |
| `kernel.ld` | メモリ配置 |
| `boot/duo.dts` | 固定ボード用の最小DTB |
| `boot/chibi-os.its` | bootm用FITの構成 |
| `Makefile` | セットアップ・ビルド・SDコピー・テスト |
| `tests/test_boot.py` | 実際の機械語とFITの検証 |

`make help` で全コマンド、`make inspect` で逆アセンブルとFIT情報を確認できます。
`make clean` は `build/` だけを削除します。旧 `make flash` は廃止し、SDコピーとU-Boot起動に変更しました。

## 次の段階

1. 例外ハンドラーでレジスタを保存し、原因をUARTへ表示する。
2. SBIタイマーと割り込みを扱う。
3. 物理ページ管理とSv39ページテーブルを実装する。
4. U-modeへの移行、システムコール、プロセスの切り替えを実装する。

## 設計に使った一次資料

- [Milk-V Duo：仕様・UART配線](https://milkv.io/docs/duo/getting-started/duo)
- [公式SDKのメモリマップ](https://github.com/milkv-duo/duo-buildroot-sdk/blob/develop/build/boards/cv180x/cv1800b_milkv_duo_sd/memmap.py)
- [公式ボードのU-Boot設定：S-mode、FIT、go無効](https://github.com/milkv-duo/duo-buildroot-sdk/blob/develop/build/boards/cv180x/cv1800b_milkv_duo_sd/u-boot/cvitek_cv1800b_milkv_duo_sd_defconfig)
- [UART0アドレス・レジスタ間隔・標準SD起動コマンド](https://github.com/milkv-duo/duo-buildroot-sdk/blob/develop/u-boot-2021.10/include/configs/cv180x-asic.h)
- [RISC-V bootm：起動前処理とカーネル引数](https://github.com/milkv-duo/duo-buildroot-sdk/blob/develop/u-boot-2021.10/arch/riscv/lib/bootm.c)
