# Handle-class input fixtures

For contributors changing parser and editor tests, this page records the origin and adaptations of preserved inputs.

The files at these paths are the handle-class adaptations of earlier AppBase fixtures. The table identifies the pre-migration inputs in Git history. Each fixture carries its original notices.

Adaptations: inherit from `handle`, replace the App Designer callback wrapper with a bound method accepting source and event, replace app registration with a default close callback and a figure destruction listener, and remove the App Designer no-output clear idiom. The fixture class identities and UI data remain unchanged. These files are preserved input data, not editor runtime code.

| Pre-migration file | Pre-migration SHA-256 |
| --- | --- |
| `AxesExplorerApp.m` | `76b71271d4ba685d4fd7d6f9eba78d1f3d89ffa9f488428cf4f0ced3836b4709` |
| `ControlGalleryApp.m` | `c7858e4ac78899ee9925915ab328fd8ab2a9f489a2057268f55979fbc483fa27` |
| `FigureToolsApp.m` | `2d7c357dc83477b5f145e827ff6ab41afdfaba98ee10f1edb506e27931849b79` |
| `LargePreviewFixtureApp.m` | `413558cdce205a09e1cc3809d1cd5d7dbc0d6462af1e9cf9b42efd8e34009e1c` |
| `NavigationDataApp.m` | `dd39fd30736c061bdb95124cd7be1f92e00d5951169fb2c1520d0da23d55f3aa` |
| `SimpleCalculatorApp.m` | `234b792b0be0a1143e27ee842ac11f560f0e95fa9f30b3822661472b141258c7` |
| `SmallPreviewFixtureApp.m` | `c28721067cd0468ef432b9b1f46e359ee208f625541a8c7083f43c6f8327b7d0` |
