[![Build Status](https://travis-ci.org/back2dos/hxx.svg?branch=master)](https://travis-ci.org/back2dos/hxx)

# HXX = JSX - JS + HX

This library provides a parser for JSX-like syntax in Haxe. To use it, you must write a generator yourself. See [`vdom.VDom.hxx` in js-virtual-dom](https://github.com/back2dos/js-virtual-dom) for an example. Each generator leads to a slightly different flavor of the language. Here you will find all the features available in HXX, but note that every flavor may handle things a bit differently.
  
## Interpolation

Unsurprisingly, you can embed expressions in HXX, either by using JSX like syntax or by using Haxe interpolation syntax, i.e. `$identifier` or `${expression}`.
  
## Control structures

HXX has support for control structures, unless disabled per `config.noControlStructures` in the parser.
  
### If

This is what conditionals look like:

```html
<if {weather == 'sunny'}>
  <sun />
<elseif {weather == 'mostly sunny'}>
  <sun />
  <cloud />
<else if {weather == 'cloudy'}>
  <cloud />
  <cloud />
  <cloud />
<else>
  <rain />
</if>
```

Note that `else` (as well as `elseif`) is optional and that both `elseif` and `else if` will work.

### Switch

Switch statements are also supported, including guards but without `default` branches (just use a catch-all `case` instead). The above example for conditionals would look like this:

```html
<switch {weather}>
  <case {'sunny'}>
  
    <sun />
    
  <case {'mostly sunny'}>

    <sun />
    <cloud />
  
  <case {cloudy} if {cloudy == 'cloudy'}>
  
    <cloud />
    <cloud />
    <cloud />
    
  <case {_}>
  
    <rain />
    
</switch>
```

### For

```html
For loops are pretty straight forward:

<for {day in forecast}>
  <weatherIcon day={day} />
</for>
```

## Spread
  
HXX has the capacity to deal with spreads, e.g. `<someTag {...properties} />`. 

## Whitespace

The treatment of whitespace depends on whether the generated structure even has any notion of whitespace or not. All HXX flavours can rely on `hxx.Generator.trimString` which handles whitespace in a manner that is quite consistent with JSX:
  
- white space on a single line makes it to the output
- white space that includes a line break is ignored

Example:

```html
<p><span>Hello</span> <span>World</span></p>

<!-- vs -->

<p>
  <span>Hello</span>
  <span>World</span>
</p>
```

The first version will retain the white space between the two spans, the second one will not.

## Imports

Within HXX code you may import other HXX code from external files. Such an import is specified as `{import "<fileName>"}`, e.g.:

```html
<div class="container">
  {import "<fileName>"}
</div>
```

By default the file name is resolved relatively to the call site, so you can put external HXX files into your classpaths, with files that depend on them. 

Some people will argue that "templates" should all be in one place and all code in another, but that's like "ordering" the information in a magazine by putting all pictures in one place and all text in another. Quite simply, you should not be doing such a thing. But if you know better, you may refer to the file by starting with `./` in which case resolution is performed relative to project root - actually to the working directory of the compilation process to be more exact.

If you specify no extension in the file name, then `.hxx` is assumed by default (unless you're using an HXX flavor that alters this).