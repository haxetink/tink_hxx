# HXX = JSX - JS + HX

This library provides a parser for JSX-like syntax in Haxe. To use it, you must write a generator yourself. See [`vdom.VDom.hxx` in js-virtual-dom](https://github.com/back2dos/js-virtual-dom) for an example.
  
Currently, the spread operator is not supported.

The language also supports imports like so:
  
```
<div class="container">
  {import "<fileName>"}
</div>
```

By default the file name is resolved relatively to the call site, so you can put external HXX files into your classpaths, with files that depend on them. 

Some people will argue that "templates" should all be in one place, but that's like "ordering" the information in a magazine by putting all pictures in one place and all text in another. Quite simply, you should not be doing such a thing. But if you know better, you may refer to the file by starting with `./` in which case resolution is performed relative to project root - actually to the working directory of the compilation process to be more exact.

If you specify no extension in the file name, then `.hxx` is assumed by default (unless you're using an HXX flavor that alters this).