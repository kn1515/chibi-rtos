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

## Makeでセットアップ・ビルドする（Ubuntu 24.04）

以下はPC上で実行するコマンドです。ESP32へ直接入力するものではありません。
最初にリポジトリを取得するためのGitと、コマンドを実行するMakeだけを用意します。

```bash
sudo apt update
sudo apt install -y git make
mkdir -p ~/esp
cd ~/esp
git clone https://github.com/kn1515/chibi-rtos.git
cd chibi-rtos
make setup
make build
```

`make setup` はUbuntu/Debianの依存パッケージをaptでインストールし、
ESP-IDF v5.5.1を `~/esp/esp-idf-v5.5.1` に取得してESP32用ツールを導入します。
パッケージ導入時にsudoパスワードを求められる場合があります。
`sudo make setup` ではなく、通常ユーザーで `make setup` を実行してください。
プロジェクトとESP-IDFのパスに空白を入れないでください。

既に必要なOSパッケージを導入済みなら `make setup SKIP_DEPS=1` でapt処理を省略できます。
SDKが既にある場合はバージョンと変更の有無を確認して再利用します。
異なるバージョンや追跡ファイルの変更がある場合は、既存SDKを書き換えずエラーにします。
新規取得はネットワーク接続が必要です。インストール途中で失敗した場合は原因を解消して再実行してください。

各Makeコマンドが必要なシェル内で `export.sh` を読み込みます。
**ターミナルを開くたびに手動で `export.sh` を実行する必要はありません。**
ターゲットはESP32固定です。`make build` はsetup済みのSDKを使い、毎回の再インストールは行いません。

SDKの保存先を変更する場合は、各コマンドに同じ `IDF_DIR` を指定します。

```bash
make setup IDF_DIR=/absolute/path/esp-idf-v5.5.1
make build IDF_DIR=/absolute/path/esp-idf-v5.5.1
```

## 書き込み・モニター

USB接続し、ポートを調べます。

```bash
ls /dev/ttyUSB* /dev/ttyACM*
```

存在しないパターンのエラーは無視し、表示された実際のポートを選びます。
以下は `/dev/ttyUSB0` の例です。書き込みは現在のファームウェアを置き換えます。

```bash
make flash-monitor PORT=/dev/ttyUSB0
```

ビルド・書き込み・シリアルモニターを順に実行します。モニターの終了はCtrl+]です。
接続待ちで進まない場合はBOOTを押しながら書き込みを開始し、接続したら離します。
Linuxで権限エラーの場合は `sudo usermod -aG dialout "$USER"` を実行し、一度ログアウトして再ログインします。
ポートがない場合は、データ対応USBケーブル、ボードのUSB-UARTドライバ、他のモニターによるポート占有を確認します。

| コマンド | 内容 |
| --- | --- |
| `make` / `make help` | コマンド一覧 |
| `make setup` | OS依存パッケージとESP-IDF・ESP32ツールを導入 |
| `make deps` | OS依存パッケージだけを導入 |
| `make build` | ファームウェアをビルド |
| `make flash PORT=/dev/ttyUSB0` | 必要なビルドを行って書き込み |
| `make monitor PORT=/dev/ttyUSB0` | シリアルモニター |
| `make flash-monitor PORT=/dev/ttyUSB0` | ビルド・書き込み・モニター |
| `make menuconfig` | 設定画面 |
| `make clean` | ESP-IDFのビルド生成物をクリーン |
| `make fullclean` | ESP-IDFのビルドディレクトリをクリーン |
| `make test` | PC上のテスト。ESP-IDFや実機は不要 |

`make clean` / `make fullclean` はsdkconfigとPC用の `.host-build` を削除しません。
`sdkconfig.defaults` は初回構成生成時に1コア動作と1000HzのFreeRTOS tickを設定します。
既存のsdkconfigがある場合は `make menuconfig` のComponent config → FreeRTOSで確認してください。
別チップ向けのsdkconfigはこのESP32専用プロジェクトへ持ち込まないでください。

## Windows・macOSの場合

このMake手順の基準環境はUbuntu 24.04です。WindowsではWSL2上のUbuntuで利用できますが、
書き込み・モニターにはUSBデバイスをWSL側へ接続する追加設定が必要です。
macOSで使う場合はBash、Make、Git、Python3とESP-IDF公式手順の依存ツールを用意し、
`make setup SKIP_DEPS=1` を使います。macOSでの動作は未検証です。
WindowsネイティブのPowerShellにはこのBash用Make手順をそのまま適用できません。
公式ESP-IDF環境から直接 `idf.py build` や `idf.py -p COM5 flash monitor` を実行できます。

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
| Makefile | セットアップ・ビルド・書き込み・テストの窓口 |
| scripts/ | 依存導入とESP-IDF呼び出し |
| CMakeLists.txt | ESP-IDFプロジェクトの定義 |
| sdkconfig.defaults | 初期設定 |
| main/CMakeLists.txt | ソースと依存コンポーネントの指定 |
| main/mini_os.h | 自作APIの宣言 |
| main/mini_os.c | ハードウェアに依存しないスケジューラ |
| main/main.c | ESP32用時計、2タスク、起動処理 |
| tests/test_mini_os.c | PCでのロジックテスト |
| tests/test_make.py | MakeからSDKへの引数転送・エラー伝播・既存SDK再利用のテスト |

## 検証

この配布物ではPCのGCCでスケジューラのテストを実行済みです。
期限前は実行しないこと、全タスク待機、同時実行可能時の巡回順、登録上限、
長い遅延後に過去分を連続実行しないこと、処理終了から待ち時間を数えることを確認しました。
Makeのコマンド転送、エラー伝播、同じSDKの再利用、異なる版・変更済みSDKの拒否は模擬SDKでテストしています。
実際のSDKダウンロード・ツール導入、ESP-IDFのクロスビルドとESP32実機での書き込み・動作は未検証です。

再実行する場合はプロジェクト直下で次を実行します。

```bash
make test
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

