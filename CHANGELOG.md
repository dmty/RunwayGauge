# Changelog

## [0.3.0](https://github.com/dmty/RunwayGauge/compare/v0.2.0...v0.3.0) (2026-08-10)


### Features

* **accounts:** add cycle intent and widget timeline ([e175e12](https://github.com/dmty/RunwayGauge/commit/e175e123e6196125d4fa031883091b5781ee423d))
* **accounts:** add multi-account poller and install ([a220350](https://github.com/dmty/RunwayGauge/commit/a22035012685063c0de0a6c617205739db90e142))
* **accounts:** add registry models and store ([f3ffa12](https://github.com/dmty/RunwayGauge/commit/f3ffa12d9c5971bb09974e7cd33d4c7be180b894))
* **accounts:** add selection and display rotation ([7adeb96](https://github.com/dmty/RunwayGauge/commit/7adeb965b0d2cf4f12abc785864d1d7a9b6c74e6))
* **accounts:** add Settings and Keychain discovery ([8b90fe0](https://github.com/dmty/RunwayGauge/commit/8b90fe0f36776f83517ae1f0741e4c16b31f3e79))
* **accounts:** add shell registry and usage commit ([b0ac516](https://github.com/dmty/RunwayGauge/commit/b0ac51604af54630ff1c45fcb2491eb774bc447e))
* **accounts:** add source adapters and discovery ([ce87c77](https://github.com/dmty/RunwayGauge/commit/ce87c7788d9d73fa6bc1acc5e535dd24ee7b6483))
* **accounts:** add usage paths and safe bootstrap ([1254d2f](https://github.com/dmty/RunwayGauge/commit/1254d2f2d2aa57a4800208cf260320e3f43d7b4c))
* **accounts:** add validation and locked mutate ([bd6d9dd](https://github.com/dmty/RunwayGauge/commit/bd6d9dd80a2e4552bae3d0428d5d21e520771c6f))
* add Edit Widget toggles for usage display options ([468528d](https://github.com/dmty/RunwayGauge/commit/468528d9209cac663d4a126e4033b54223bbd812))
* add locked atomic usage commit in UsageCore ([1113905](https://github.com/dmty/RunwayGauge/commit/111390547e4707449aae9dd7925357ef14191a66))
* add manual usage refresh and document Edit Widget options ([44668b0](https://github.com/dmty/RunwayGauge/commit/44668b03403e6685b5f4edae9b070da0674db1a4))
* add runwaygauge-helper poll and write commands ([2e5ca9d](https://github.com/dmty/RunwayGauge/commit/2e5ca9dfd939829753ee4184ff2d3426735ec6bf))
* add usage display option filtering ([c5466f6](https://github.com/dmty/RunwayGauge/commit/c5466f6fb8ef13f8ed7fb1ab81442908b347ead0))
* add usage schema 2 fields and severity-aware levels ([9b9a38a](https://github.com/dmty/RunwayGauge/commit/9b9a38a3fbb5cb192996ba02b76e3f123736e97c))
* map Anthropic OAuth and statusline payloads into usage records ([f4b01a6](https://github.com/dmty/RunwayGauge/commit/f4b01a606499dbc7c0cf69f31f5f241ca06a115d))
* ship Swift usage helper via launchd and statusline ([cb0011d](https://github.com/dmty/RunwayGauge/commit/cb0011d9c8e1c84f3e05d32cd986ed0a8dfe8f36))
* **widget:** add corner cycle and settings controls ([60b19b5](https://github.com/dmty/RunwayGauge/commit/60b19b5463ccf202d7ee6f13bd7adc6216893d77))


### Bug Fixes

* **accounts:** prune stale Keychain rows on refresh ([87bf4d3](https://github.com/dmty/RunwayGauge/commit/87bf4d30673430e2d59a60da1925e187fdeabe30))
* expose UsageDisplayOptions public initializer ([ae4085f](https://github.com/dmty/RunwayGauge/commit/ae4085f8bb0afe0c481cb2f6840743e210288971))
* filter display defaults, force helper reconfig, universal helper binary ([032bd79](https://github.com/dmty/RunwayGauge/commit/032bd79136fe8c9041536641ac2f25a4beefa34d))
* poll on OAuth age not statusline mtime ([46c17dc](https://github.com/dmty/RunwayGauge/commit/46c17dc53724515239f41a52ff6590de0a7155ba))
* preserve enriched windows and last-good timestamps on helper writes ([daa0981](https://github.com/dmty/RunwayGauge/commit/daa0981ad49fb93fc25c3e40d83224bb8a2d01b4))
* tighten statusline merge and skip empty statusline writes ([e03471e](https://github.com/dmty/RunwayGauge/commit/e03471e706de8e3a26194c8ebd7110bcbc3dbfd4))
* use BSD flock for usage commit lock parity with shell ([5ebbf39](https://github.com/dmty/RunwayGauge/commit/5ebbf39a11eacf3258ace4cfc0a4a0fd1a1b3107))

## [0.2.0](https://github.com/dmty/RunwayGauge/compare/v0.1.0...v0.2.0) (2026-08-04)


### Features

* add freshness evaluation with rollover detection ([08258e3](https://github.com/dmty/RunwayGauge/commit/08258e3081932c2a279ecd95b78cbfc0b4a5ad58))
* add helper setup copy-and-install path ([9b19a54](https://github.com/dmty/RunwayGauge/commit/9b19a5424b459c888440df146ae13d224789f9c0))
* add macOS app icon ([ce13cb2](https://github.com/dmty/RunwayGauge/commit/ce13cb242e56313fbc5c56b398214f86b46a7122))
* add release app build and DMG packaging scripts ([6fb5a04](https://github.com/dmty/RunwayGauge/commit/6fb5a04a5653e888649435ae38dbb98fa3f4d77d))
* add reset and age formatting ([595a3b7](https://github.com/dmty/RunwayGauge/commit/595a3b7b9d4ddf032a6f25dc3118a0318ee482d1))
* add Set up data collection button ([60b6c40](https://github.com/dmty/RunwayGauge/commit/60b6c400efa607098b2465c5f8e21fe359b0e83b))
* add statusline install and uninstall scripts ([24b5c24](https://github.com/dmty/RunwayGauge/commit/24b5c24b6b286de5b80214cf27623b8e11d19e1b))
* add statusline usage writer and wrapper ([2625a72](https://github.com/dmty/RunwayGauge/commit/2625a729d0c9980253b49874d856ef57092379bb))
* add usage endpoint probe ([da152ec](https://github.com/dmty/RunwayGauge/commit/da152ec6150099eacc3e71aaf003bf5e726d3417))
* add usage level thresholds ([3131484](https://github.com/dmty/RunwayGauge/commit/31314841854e1de1dd540f3d4c7fb9afb98693fd))
* add usage poller and launchd agent ([6d31ee6](https://github.com/dmty/RunwayGauge/commit/6d31ee6ab2d60f205ea4ae5d7c87e9866d643e54))
* add usage record model and decoding ([c3123c4](https://github.com/dmty/RunwayGauge/commit/c3123c40e0df7e486ffabcdb873262cd08ed2e71))
* add usage store and widget state mapping ([488d21a](https://github.com/dmty/RunwayGauge/commit/488d21a146265cd1fb4f71d4c37a7dfeb4bcd6b0))
* bundle helper scripts into app Resources ([fbc8831](https://github.com/dmty/RunwayGauge/commit/fbc8831d732a78176337f5048cb6967c71b3ad37))
* grant widget read access to the data directory ([0dd9aa2](https://github.com/dmty/RunwayGauge/commit/0dd9aa22edca5f215ee1b633c09a95f9dbb08765))
* record oauth usage endpoint fixture ([99f5ae9](https://github.com/dmty/RunwayGauge/commit/99f5ae9526de457357ffb7ae4a620cbbbc512cbd))
* render claude code usage in small and medium widgets ([3a183bc](https://github.com/dmty/RunwayGauge/commit/3a183bcc1c5641e82243d4ae3b7266bd4dc34508))
* scaffold host app and widget extension ([fc75558](https://github.com/dmty/RunwayGauge/commit/fc755589e9433bf9bbd77ecf4f11891ea6a1618e))
* scaffold Icon Composer Liquid Glass app icon ([79147f7](https://github.com/dmty/RunwayGauge/commit/79147f7d1603477f34be3efe3b72a07d5994c634))
* show data file status in the host app ([4bd5c58](https://github.com/dmty/RunwayGauge/commit/4bd5c5831868ef7c597991a7e2a3a7af0a9e9edc))


### Bug Fixes

* allow host app to read widget usage file ([fb2009f](https://github.com/dmty/RunwayGauge/commit/fb2009f8d46f5df248603eca23489d24641da9cc))
* cap helper setup output at utf-8 boundary ([82303b5](https://github.com/dmty/RunwayGauge/commit/82303b54647a9d3a2072dfedf35cd11defa6396e))
* distinguish missing usage file from unreadable ([9df86de](https://github.com/dmty/RunwayGauge/commit/9df86de7fda2dcba04a3860ca9d2170b71af0035))
* drop untestable xcodebuild test step from CI ([1083df8](https://github.com/dmty/RunwayGauge/commit/1083df80bc43787db4f35063a2686eff3000bdd4))
* isolate helper-setup exit-code test destinations ([3bfd79e](https://github.com/dmty/RunwayGauge/commit/3bfd79e3c673cc7367109d30bd5622b648eccf59))
* keep fake statusline output newline-free ([0d8bc34](https://github.com/dmty/RunwayGauge/commit/0d8bc34fda8b009836ad0576f62122b1fe4f4fbc))
* point host app at widget container usage file ([d312102](https://github.com/dmty/RunwayGauge/commit/d3121027f6f23776ccf96a6049fe3c8cb72b5ff2))
* read usage data from extension container ([c5bb6b3](https://github.com/dmty/RunwayGauge/commit/c5bb6b3c1d985d9c3534039b16ab4c6719e05234))
* resolve usage path inside sandbox container ([8640ed0](https://github.com/dmty/RunwayGauge/commit/8640ed00bd016173bbb5c02c09262be5ebc654e3))
* set bundle identifiers in Info plists ([8eb185b](https://github.com/dmty/RunwayGauge/commit/8eb185bced885df50454c880bade9bb524592ad2))

## Changelog
