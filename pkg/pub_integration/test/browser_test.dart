// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

import 'package:pub_integration/script/base_setup_script.dart';
import 'package:pub_integration/src/headless_env.dart';
import 'package:pub_integration/src/fake_credentials.dart';
import 'package:pub_integration/src/fake_pub_server_process.dart';

void main() {
  final coverageDir = Platform.environment['COVERAGE_DIR'];
  final trackCoverage =
      coverageDir != null || Platform.environment['COVERAGE'] == '1';

  group('browser', () {
    late FakePubServerProcess fakePubServerProcess;
    late BaseSetupScript script;
    HeadlessEnv? headlessEnv;
    final httpClient = http.Client();

    setUpAll(() async {
      fakePubServerProcess = await FakePubServerProcess.start();
      await fakePubServerProcess.started;
    });

    tearDownAll(() async {
      await script.close();
      await headlessEnv?.close();
      await fakePubServerProcess.kill();
      httpClient.close();
      headlessEnv?.printCoverage();
      if (coverageDir != null) {
        await headlessEnv?.saveCoverage(
            p.join(coverageDir, 'puppeteer'), 'browser');
      }
    });

    test('base setup: publish packages', () async {
      script = BaseSetupScript(
        pubHostedUrl: 'http://localhost:${fakePubServerProcess.port}',
        credentialsFileContent: fakeCredentialsFileContent(),
      );
      await script.publishPackages();
    });

    test('base setup: update pub site', () async {
      await script.updatePubSite();
    });

    // Starting browser separately, as it may timeout when run together with the
    // server startup.
    test('start browser', () async {
      headlessEnv = HeadlessEnv(trackCoverage: trackCoverage);
      await headlessEnv!.startBrowser(
          origin: 'http://localhost:${fakePubServerProcess.port}');
    });

    test('landing page', () async {
      await headlessEnv!.withPage(
        user: FakeGoogleUser.withDefaults('dev@example.org'),
        fn: (page) async {
          await page.goto('http://localhost:${fakePubServerProcess.port}',
              wait: Until.networkIdle);

          // checking if there is a login button
          await page.hover('#-account-login');
        },
      );
    });

    test('listing page', () async {
      await headlessEnv!.withPage(
        user: FakeGoogleUser.withDefaults('dev@example.org'),
        fn: (page) async {
          await page.goto(
              'http://localhost:${fakePubServerProcess.port}/packages',
              wait: Until.networkIdle);

          // check package list
          final packages = <String?>{};
          for (final item in await page.$$('.packages .packages-title a')) {
            final text = await (await item.property('textContent')).jsonValue;
            packages.add(text as String?);
          }
          expect(packages, {'_dummy_pkg', 'retry'});
        },
      );
    });

    test('package page', () async {
      await headlessEnv!.withPage(
        user: FakeGoogleUser.withDefaults('dev@example.org'),
        fn: (page) async {
          await page.goto(
              'http://localhost:${fakePubServerProcess.port}/packages/retry',
              wait: Until.networkIdle);

          // check pub score
          final pubScoreElem = await page
              .$('.packages-score-health .packages-score-value-number');
          final pubScore =
              await (await (pubScoreElem).property('textContent')).jsonValue;
          expect(pubScore, '100');

          // check header with name and version
          Future<void> checkHeaderTitle() async {
            final headerTitle = await page.$('h1.title');
            final headerTitleText =
                await (await headerTitle.property('textContent')).jsonValue;
            expect(headerTitleText, contains('retry 2.0.1'));
          }

          await checkHeaderTitle();
          await _checkCopyToClipboard(page);

          await page.goto(
              'http://localhost:${fakePubServerProcess.port}/packages/retry/versions/2.0.1',
              wait: Until.networkIdle);
          await checkHeaderTitle();

          await page.goto(
              'http://localhost:${fakePubServerProcess.port}/packages/retry/versions/2.0.01',
              wait: Until.networkIdle);
          await checkHeaderTitle();

          await page.goto(
              'http://localhost:${fakePubServerProcess.port}/packages/retry/license',
              wait: Until.networkIdle);
          await checkHeaderTitle();
        },
      );
    });
  }, timeout: Timeout.factor(testTimeoutFactor));
}

Future _checkCopyToClipboard(Page page) async {
  // we have an icon that we can hover
  final copyIconHandle = await page.$('.pkg-page-title-copy-icon');
  await copyIconHandle.hover();

  // feedback must not be visible at first
  final feedbackHandle = await page.$('.pkg-page-title-copy-feedback');
  expect(await feedbackHandle.isIntersectingViewport, false);

  // triggers copy to clipboard + feedback
  await copyIconHandle.click();

  // feedback is visible
  expect(await feedbackHandle.isIntersectingViewport, true);

  // clipboard has the content
  expect(
    await page.evaluate('() => navigator.clipboard.readText()'),
    'retry: ^2.0.1',
  );

  // feedback should not be visible after 2.5 seconds
  await Future.delayed(Duration(milliseconds: 2600));
  expect(await feedbackHandle.isIntersectingViewport, false);
}
