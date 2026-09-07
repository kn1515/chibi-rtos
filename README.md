# chibi-rtos

ESP32で作るミニOS・第1段階

これは、RTOS自作の入門として作った「協調型・スタックレスのタスクスケジューラ」です。
ESP-IDFのFreeRTOS上で動作します。独立したベアメタルRTOSではありません。
自作する部分はタスク管理表・実行順の選択・待ち時間の管理です。
起動、ハードウェアの初期化、時計、シリアル出力、下層のCPU管理はESP-IDFに任せます。

## 対象

- 元祖ESP32搭載ボード（ESP32-WROOM-32 / ESP32-DevKitC等）、USBデータケーブル。
- ESP-IDF v5.5.1を手順の基準として固定。最新版という意味ではありません。
- センサーやLEDの配線は不要。シリアルモニターだけで確認できます。
- ESP32-C3/S3等は別チップです。この手順のターゲットは `esp32` です。

## 動くもの

起動直後にAとBを実行し、それ以降Aは処理終了から500ms以上、Bは1000ms以上待って再実行します。
1回のスケジューラ呼び出しで実行するタスクは最大1個。最大4個まで登録できます。
複数が実行可能なら、前回実行したタスクの次から巡回して選びます。

## Ubuntu 24.04での準備

以下はPC上で実行するコマンドです。ESP32へ直接入力するものではありません。
プロジェクトとESP-IDFのパスに空白を入れないでください。

```bash
sudo apt update
sudo apt install -y git wget flex bison gperf python3 python3-pip python3-venv cmake ninja-build ccache libffi-dev libssl-dev dfu-util libusb-1.0-0 unzip build-essential
mkdir -p ~/esp
cd ~/esp
git clone -b v5.5.1 --recursive https://github.com/espressif/esp-idf.git esp-idf-v5.5.1
cd ~/esp/esp-idf-v5.5.1
./install.sh esp32
. ./export.sh
idf.py --version
```

新しいターミナルを開くたびに、次を実行します。

```bash
. ~/esp/esp-idf-v5.5.1/export.sh
```

Windowsネイティブの場合は公式ESP-IDF Windowsインストーラーでv5.5.1を導入し、
ESP-IDF用のコマンドプロンプト/PowerShellから下記の `idf.py` を実行します。
Linux用の `apt` や `export.sh` は使いません。ポートは `COM5` 等になります。
WSL2ではUSBデバイスをWSLへ接続する追加設定が必要です。この教材のLinux手順は
USB接続されたボードがLinuxから見えていることを前提とします。

## 取得・ビルド・書き込み

このリポジトリを取得し、プロジェクト直下でビルドします。

```bash
cd ~/esp
git clone https://github.com/kn1515/chibi-rtos.git
cd chibi-rtos
idf.py set-target esp32
idf.py build
```

`sdkconfig.defaults` は、初回構成生成時に1コア動作と1000HzのFreeRTOS tickを設定します。
既存のsdkconfigがあるプロジェクトへファイルだけコピーした場合は、`idf.py menuconfig`
のComponent config → FreeRTOSで確認してください。このリポジトリには生成済みのsdkconfigを含めていません。

USB接続し、ポートを調べます。

```bash
ls /dev/ttyUSB* /dev/ttyACM*
```

存在しないパターンのエラーは無視し、表示された実際のポートを選びます。
以下は `/dev/ttyUSB0` の例です。書き込みは現在のファームウェアを置き換えます。

```bash
idf.py -p /dev/ttyUSB0 flash monitor
```

WindowsでCOM5の場合は次のとおりです。

```powershell
idf.py -p COM5 flash monitor
```

終了はCtrl+]。接続待ちで進まない場合はBOOTを押しながら書き込みを開始し、接続したら離します。
Linuxで権限エラーの場合は `sudo usermod -aG dialout "$USER"` を実行し、一度ログアウトして再ログインします。
ポートがない場合は、データ対応USBケーブル、ボードのUSB-UARTドライバ、他のモニターによるポート占有を確認します。

## 出力の読み方

次は形式を示す架空の例で、実機測定ログではありません。

```text
mini_os: cooperative scheduler on ESP-IDF
[300 ms] A: 1
[301 ms] B: 1
[801 ms] A: 2
[1302 ms] B: 2
[1303 ms] A: 3
```

時計はapp_main開始時に0へリセットしていません。初期値は0とは限りません。
500ms/1000msは「処理終了後の最小待ち時間」で、厳密な周期ではありません。
出力処理や他のタスクの実行により遅れ、長期的にはずれが累積します。
順序も期限や出力の所要時間で変わります。Aが概ねBの2倍の頻度で増えることを確認してください。

## 仕組みと約束

1. `os_add_task` が関数、保持データ、次回実行時刻をタスク管理表に登録します。
2. `os_step` が、待ち時間を終えたタスクを巡回順に最大1個選びます。
3. 選ばれた関数は短い処理をし、次回までの待ち時間を `return` します。
4. スケジューラは終了時刻に待ち時間を足し、次の実行可能時刻を保存します。
5. `vTaskDelay(1)` は下層FreeRTOSへ実行時間を返します。この設定では1tickは1msです。
   実際の再開までの時間はtickの位相や他の処理に左右されます。

`return 500;` 自体は500msブロックする命令ではありません。関数から戻り、管理表へ
「500ms後から再実行可能」と記録するための戻り値です。その間に別のタスクを実行できます。
再実行は関数の先頭からです。途中の行やローカル変数は復元しません。
継続データはmain.cのカウンターのように寿命のある構造体/変数を `arg` で渡してください。

タスクに無限ループや長時間の待機を入れると、自作スケジューラ内の他のタスクが止まります。
長い仕事は短いステップへ分割します。下層FreeRTOSはプリエンプトできますが、
この自作スケジューラはタスク関数を強制中断できません。
`os_init` と登録は実行ループの開始前に行い、タスク内・割り込み・別FreeRTOSタスクから
これらのAPIを呼びません。`os_step` も再帰呼び出し禁止です。

これは時間制約のある処理を学ぶ土台です。優先度、タスク専用スタック、コンテキスト切替、
独自割り込みハンドラ、期限保証はまだありません。printfも実行時間が一定でなく、
ハードリアルタイム性は保証しません。

## ファイル

| ファイル | 役割 |
| --- | --- |
| CMakeLists.txt | ESP-IDFプロジェクトの定義 |
| sdkconfig.defaults | 初期設定 |
| main/CMakeLists.txt | ソースと依存コンポーネントの指定 |
| main/mini_os.h | 自作APIの宣言 |
| main/mini_os.c | ハードウェアに依存しないスケジューラ |
| main/main.c | ESP32用時計、2タスク、起動処理 |
| tests/test_mini_os.c | PCでのロジックテスト |

## 検証

この配布物ではPCのGCCでスケジューラのテストを実行済みです。
期限前は実行しないこと、全タスク待機、同時実行可能時の巡回順、登録上限、
長い遅延後に過去分を連続実行しないこと、処理終了から待ち時間を数えることを確認しました。
ESP-IDFのクロスビルドとESP32実機での書き込み・動作は未検証です。

再実行する場合はプロジェクト直下で次を実行します。

```bash
gcc -std=c11 -Wall -Wextra -Werror -pedantic -I main main/mini_os.c tests/test_mini_os.c -o /tmp/test_mini_os
/tmp/test_mini_os
```

## 次の段階

まずBの `return 1000` を `return 2000` に変更し、書き込み直して頻度を確認します。
次に3つ目のタスクを登録し、管理表と実行順を観察します。
その後、優先度、イベント待ち、タスク専用スタックとコンテキスト切替、
タイマー割り込みによるプリエンプションの順に進めます。
FreeRTOSを取り除く段階では、ESP32の正確な型番・CPUアーキテクチャを確定し、
起動コード、リンカスクリプト、例外/割り込み、時計、UARTを含む別の基盤が必要です。
このサンプルからFreeRTOSヘッダーだけを消して独立OSにすることはできません。

## 一次資料

- セットアップとビルド・書き込み: https://docs.espressif.com/projects/esp-idf/en/v5.5.1/esp32/get-started/linux-macos-setup.html
- ESP-IDFのFreeRTOS: https://docs.espressif.com/projects/esp-idf/en/v5.5.1/esp32/api-reference/system/freertos_idf.html
- ESP Timer: https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/esp_timer.html

