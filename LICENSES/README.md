# Apple dependency licenses

This directory preserves the license texts for the six external Swift packages resolved for the
Apple app targets. It covers this Apple dependency set, including MarkdownUI's transitive packages;
it is not an exhaustive inventory of Android dependencies or every tool used in the repository.

The versions and revisions below match the committed
[`Package.resolved`](../Strand.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved).
Each local text is copied byte for byte from an unchanged checkout at the recorded revision. The
upstream links identify that exact source revision rather than a moving default branch.

| Dependency | Version | Preserved text | Upstream text at the resolved revision |
|---|---|---|---|
| GRDB.swift | 6.29.3 | [GRDB.swift-LICENSE.txt](GRDB.swift-LICENSE.txt) | [LICENSE](https://github.com/groue/GRDB.swift/blob/2cf6c756e1e5ef6901ebae16576a7e4e4b834622/LICENSE) |
| ZIPFoundation | 0.9.20 | [ZIPFoundation-LICENSE.txt](ZIPFoundation-LICENSE.txt) | [LICENSE](https://github.com/weichsel/ZIPFoundation/blob/22787ffb59de99e5dc1fbfe80b19c97a904ad48d/LICENSE) |
| MarkdownUI | 2.4.1 | [MarkdownUI-LICENSE.txt](MarkdownUI-LICENSE.txt) | [LICENSE](https://github.com/gonzalezreal/swift-markdown-ui/blob/5f613358148239d0292c0cef674a3c2314737f9e/LICENSE) |
| NetworkImage | 6.0.1 | [NetworkImage-LICENSE.txt](NetworkImage-LICENSE.txt) | [LICENSE](https://github.com/gonzalezreal/NetworkImage/blob/2849f5323265386e200484b0d0f896e73c3411b9/LICENSE) |
| swift-cmark | 0.8.0 | [swift-cmark-COPYING.txt](swift-cmark-COPYING.txt) | [COPYING](https://github.com/swiftlang/swift-cmark/blob/924936d0427cb25a61169739a7660230bffa6ea6/COPYING) |
| JOSESwift | 3.0.0 | [JOSESwift-LICENSE.txt](JOSESwift-LICENSE.txt) | [LICENSE](https://github.com/airsidemobile/JOSESwift/blob/c2664a902e75c0426a1d43132bd4babc6fd173d3/LICENSE) |

GRDB.swift, ZIPFoundation, MarkdownUI and NetworkImage supply MIT license texts. JOSESwift supplies
Apache License 2.0. The swift-cmark `COPYING` file contains the cmark redistribution terms and
additional component notices; the entire file is preserved.

These dependencies retain their own terms and copyright notices. The repository's
[PolyForm Noncommercial license](../LICENSE) does not relicense their source. When a dependency
version changes, refresh its text from the resolved revision and update this inventory.

See [`NOTICE`](../NOTICE) and [`ATTRIBUTION.md`](../ATTRIBUTION.md) for the direct NOOP upstream and
earlier interoperability research. This dependency inventory does not resolve the inherited
`my-whoop` provenance discrepancy recorded there. Source and binary redistribution require that provenance
review and inclusion of the notices required by the dependencies actually included in the build.
