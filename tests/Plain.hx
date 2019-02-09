class Plain {
  macro static public function hxx(e) {
    var ctx = new tink.hxx.Generator().createContext();
    return ctx.generateRoot(
      tink.hxx.Parser.parseRoot(e, { 
        defaultExtension: 'hxx', 
        noControlStructures: false, 
        defaultSwitchTarget: macro __data__,
        isVoid: ctx.isVoid,
        treatNested: ctx.generateRoot,
      })
    );
  }
}