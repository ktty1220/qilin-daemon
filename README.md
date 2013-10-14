# qilin-daemon - Node.jsでホットデプロイをサポートするデーモン

Node.jsの弱点である「スクリプトが落ちる = サーバーが落ちる」、「スクリプトを更新したらサーバーを再起動する必要がある」という問題点をクリアする[qilin](https://github.com/atsuya/qilin)というモジュールがnpmに登録されています。

qilinはNode.jsのcluster機能を利用して複数のworkerを立ち上げて管理し、スクリプトエラーなどで落ちた場合に自動で再起動したり、現在の接続を維持したままアプリケーションを更新できるホットデプロイ機能を提供しています。

qilinについての詳しい説明は<http://atsuya.github.io/blog/2012/10/15/qilin/>をご覧ください。

qilin-daemonは、qilinモジュールを利用して以下の機能を提供するアプリケーション管理デーモンです。

1. 指定されたファイル・ディレクトリを監視し、変更があった場合に自動でworkerを再起動する。

2. httpでコマンドを送信する事により、workerの再起動や各workerのCPU・メモリ使用状況をJSON形式で取得したりできる(Windowsは未対応)。

3. 管理デーモンにhttpでコマンドを送る際にベーシック認証が使用できる。

## インストール

ダウンロードもしくは`git clone`で取得したqilin-daemonのディレクトリで以下のコマンドを実行します。

    $ npm install

なお、CPU・メモリの使用状況の取得には[usage](https://github.com/arunoda/node-usage)モジュールを使用していますが、Windowsには対応していません。したがって、Windows上でインストールする場合はusageモジュールは無意味なので、`package.json`からusageモジュールの記述を消してから上記コマンドを実行する事をお勧めします(あっても構いませんが、usageモジュールはコンパイルが必要でVisualStudioがインストールされていないとnpmでエラーとなります)。

## 使用方法

1. `qilin-daemon.json`という設定ファイルを作成します。

    サンプル(app.jsというアプリケーションを管理するデーモン)

        {
          "exec": "app.js",
          "args": [],
          "workers": 3,
          "daemon_port": 9999,
          "worker_disconnect_timeout": 5000,
          "silent": false,
          "watch": [ "libs", "routes", "views", "config/config.json" ],
          "auth_username": "admin",
          "auth_password": "admin"
        }

2. `qilin-daemon.json`のあるディレクトリで以下のコマンドを実行します。

        $ coffee /path/to/qilin-daemon.coffee

    別のディレクトリから実行する場合は、引数に`qilin-daemon.json`のパスを指定してください。

        $ coffee /path/to/qilin-daemon.coffee /path/to/qilin-daemon.json

    ※ coffee-scriptで実行するのが嫌な場合はjavascriptにコンパイルしてご利用ください。

3. 以下の様なメッセージが出てworkerプロセスが起動します。

        2013-10-13T02:50:34.795Z - info: Worker[2] is up: 6912
        2013-10-13T02:50:34.803Z - info: Worker[1] is up: 3308
        2013-10-13T02:50:34.818Z - info: Worker[3] is up: 8500
        [daemon] app.js x 3 started (daemon_port: 9999)

4. curlで管理デーモンと通信してみます。

        $ curl http://localhost:9999/info
        {"error":"unauthorized"}

    エラーが発生しました。`qilin-daemon.json`でベーシック認証の設定をしているので、ユーザー名とパスワードを指定して再度実行します。

        $ curl http://admin:admin@localhost:9999/info
        {
          "result": {
            "master": {
              "pid": 7108,
              "cpu": 6.35,
              "mem": 22.68
              "uptime": {
                "days": 0,
                "hours": 0,
                "minutes": 3,
                "seconds": 22
              },
            },
            "workers": [
              {
                "pid": 8276,
                "cpu": 4.1,
                "mem": 10.84
              },
              {
                "pid": 7796,
                "cpu": 4.11,
                "mem": 10.85
              },
              {
                "pid": 7660,
                "cpu": 3.94,
                "mem": 10.85
              }
            ],
            "total": {
              "cpu": 18.5,
              "mem": 55.22
            }
          },
        }

    ※見やすくするためにJSONを展開しています。

    masterプロセス(管理デーモン)とworkerプロセス(app.js x 3)の各リソース使用状況が確認できました。

5. app.jsに何か変更を加えて5秒ほど待つとworkerプロセスが再起動します。

        [daemon] killed workers
        2013-10-13T03:01:18.555Z - info: Worker[3] died: 7660
        2013-10-13T03:01:18.559Z - info: Worker[1] died: 8276
        2013-10-13T03:01:18.561Z - info: Worker[2] died: 7796
        2013-10-13T03:01:18.631Z - info: Worker[4] is up: 8864
        2013-10-13T03:01:18.656Z - info: Worker[5] is up: 7156
        2013-10-13T03:01:18.670Z - info: Worker[6] is up: 9992
        [daemon] restart workers

    即座に再起動しないのは、複数のファイルを大量に更新した際に、その度にworkerが再起動するのを防止する為です。最後の変更があってからn秒(デフォルトは5秒)何もなければworkerが再起動するようになっています。

## qilin-daemon.jsonの設定詳細

* exec (文字列, __必須__)

    実行するNode.jsアプリケーションのファイル名(.js)を指定します。coffeeスクリプトを指定したい場合は別途以下のようなjsファイルを作成して、そちらからcoffeeスクリプトを呼び出すようにしてください。

    server.js

        require('coffee-script');
        require('./app');

    qilin-daemon.json

        {
          "exec": "server.js",

* args (配列, デフォルト: `[]`)

    `exec`で指定したアプリケーションを起動する際に引数を渡す場合に指定してください。

* silent (真偽値, デフォルト: `false`)

    `true`の場合、アプリケーション内でconsole.logなどで出力される内容を破棄します。

    qilin自体から発生するログメッセージはこのオプションでは消えません。qilinのメッセージは`NODE_ENV`が`'production'`の場合は`warning`レベル以上、そうでない場合は`info`レベル以上のメッセージが自動で表示されます。

* workers (数値, デフォルト: `1`) 

    起動させるworkerの数を指定します。CPUの数が良いらしいです。

* worker\_disconnect\_timeout (数値, デフォルト: `5000`)

    アプリケーションやサーバー側で`keep-alive`が有効にされている場合など、その接続がタイムアウトするまで何分もworkerの再起動ができない場合があります。そういった理由で指定時間以上再起動が待たされている時に強制的にクライアントとの接続を閉じてworkerを再起動するまでの時間をミリ秒で指定します。

    __大体の場合はクライアントとの通信は正常に終了していて、`keep-alive`による空接続状態が残っているだけなので強制的に接続を閉じても問題はありませんが、サーバー側で本当に時間のかかる処理をしている場合には不正な中断となってしまいます。サーバー側の処理にかかる時間を考慮した上で、各アプリケーションに適した値を指定してください。__

* daemon\_port (数値)

    コマンドでやり取りする管理デーモンのポート番号です。指定しない場合はhttpによる管理デーモンとのコマンド対話通信はできません。

* watch (配列, デフォルト: `[]`)

    ホットデプロイのトリガーとなるファイル・ディレクトリを指定します。ここで指定されたファイル・ディレクトリに変更があると自動でworkerが再起動します。なお、何も指定しなくても`exec`で指定したファイルは監視対象となります。

* reload\_delay (数値, デフォルト: `5000`) 

    監視するファイル・ディレクトリが変更されてからworkerを再起動するまでの待機時間をミリ秒で指定します。その待機時間中にファイル・ディレクトリの更新がなくなったらworkerを再起動します。この値が小さすぎると、大量のファイルが更新された時に複数の更新メッセージが飛んできてその度にworkerを再起動してしまいます。

* auth\_username (文字列)

    管理デーモンと通信する際にベーシック認証を用いる場合に指定するユーザー名です。`auth_password`も指定する必要があります。

* auth\_password (文字列)

    管理デーモンと通信する際にベーシック認証を用いる場合に指定するパスワードです。`auth_username`も指定する必要があります。

## 管理デーモンの提供するhttpコマンド

    http://<サーバー名>:<管理デーモンのポート番号>/<コマンド>

という形でGETリクエストを送信する事によってJSON形式で結果を取得できます。

JSONの形は`{ error: <エラーメッセージ>, result: <結果> }`となります。

* info

    管理デーモンおよびworkerプロセスのプロセスIDとCPU・メモリ使用状況を取得します。メモリの数値はMB単位です。

    管理デーモンの情報(master)に関しては、プロセスが起動してからの経過時間情報も返します。

    __なお、Windows上で実行している場合はCPU・メモリ使用状況は取得できません(すべて0になります)。__

* reload

    workerプロセスを明示的に再起動させます。

* quit

    管理デーモンを終了させます。workerプロセスも終了します。

## exampleディレクトリ

簡単なサンプルです。このディレクトリ上で

    $ coffee ../qilin-daemon.coffee

と実行するとsample.jsがqilin-daemonの管理下で実行されます。

## centos-serviceディレクトリ

qilin-daemon.coffeeをCentOSのサービスに登録する場合に使用する起動スクリプトの雛形です。

qilindファイル内の各種設定を環境に合わせて記述して/etc/init.d/に置き、

    $ chkconfig --add qilind
    $ chkconfig qilind on

とするとCentOSのサービスに登録されます。

## 参考にさせていただいたサイト

* [qilin - 思った事](http://atsuya.github.io/blog/2012/10/15/qilin/)
* [Node.jsのcluster.disconnectの挙動とGracefulリスタート - yo_waka's blog](http://waka.hatenablog.com/entry/2013/01/22/190701)
* [Node.js道場1stシーズン課題プレイバック（序の段） - Qiita [キータ]](http://qiita.com/mazzo46@github/items/1b1fac54d72110ebc508)

## Changelog

### 0.1.1 (2013-10-14)

* httpコマンド`info`で取得する情報に管理デーモンのuptimeを追加
* pidファイル出力設定追加
* CentOS用起動スクリプト追加

### 0.1.0 (2013-10-13)

* 初版リリース

## ライセンス

[MIT license](http://www.opensource.org/licenses/mit-license)で配布します。

&copy; 2013 [ktty1220](mailto:ktty1220@gmail.com)
