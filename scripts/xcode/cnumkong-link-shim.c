// Temporary relocatable-link marker for NumKong's header-only CNumKong target.
//
// NumKong 7.8.2 keeps its implementation in CNumKongDispatch, while CNumKong
// only exposes public headers. Xcode's SwiftPM integration still adds the
// nonexistent CNumKong.o to transitive app links (swift-package-manager#5706).
// The app pre-build phase compiles this substantive marker object at the exact
// path Xcode expects. Remove it when NumKong ships a source in CNumKong.
const unsigned int nk_vreader_cnumkong_linker_shim = 1u;
