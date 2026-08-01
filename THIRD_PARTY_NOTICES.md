# Third-party notices

## swift-markdown 0.8.0 (direct dependency)

Embercue uses the parser target from [swiftlang/swift-markdown](https://github.com/swiftlang/swift-markdown)
at the exact `0.8.0` tag to parse locally supplied Markdown. The Embercue renderer does not resolve
links, images, or attachments.

Copyright (c) 2021 Apple Inc. and the Swift project authors.

Licensed under Apache License 2.0 with the Swift Runtime Library Exception. The corresponding
upstream `LICENSE.txt` and `NOTICE.txt` are retained under `ThirdParty/swift-markdown/` and in
the packaged application's `Contents/Resources/Licenses/swift-markdown/` directory.

## swift-cmark 0.8.0 (transitive dependency)

`swift-markdown` resolves [swiftlang/swift-cmark](https://github.com/swiftlang/swift-cmark)
at 0.8.0. Its complete upstream `COPYING` inventory is retained under
`ThirdParty/swift-cmark/` and in the packaged application's
`Contents/Resources/Licenses/swift-cmark/` directory.
