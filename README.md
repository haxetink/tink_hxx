[![Build Status](https://travis-ci.org/haxetink/tink_hxx.svg?branch=master)](https://travis-ci.org/haxetink/tink_hxx)
[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/haxetink/public)

# HXX = JSX - JS + HX

This library provides a parser for JSX-like syntax in Haxe, as well as a generator. The documentation below describes the syntax permitted by the parser and the semantics used by the generator. You may roll your own generator on top of the parsed syntax tree (see `tink.hxx.Node`), in which case other rules apply.
  
## Interpolation

Unsurprisingly, you can embed expressions in HXX, either by using JSX like syntax or by using Haxe interpolation syntax, i.e. `$identifier` or `${expression}`.
  
## Control structures

HXX has support for a few control structures. Their main reason for existence is that implementing a reentrant parser with autocompletion support proved rather problematic in Haxe 3.

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

For loops are pretty straight forward:

```html
<for {day in forecast}>
  <weatherIcon day={day} />
</for>
```

## Let

You can define variables with `<let>` and access them within the tag.

```html
<let foo={new Foo()} ids={[1,2,3,4]}>
  <for {id in ids}>
    <button onclick={foo.handleClick(id)}>Test</button>
  </for>
</let>
```

## Tag Semantics

When HXX encounters a (non-keyword) node, it is resolved in the current scope and after that in a global fallback scope (ordinarily the HTML tags are defined here). A node name (i.e. a dot path) may resolve to any of the following:

1. a function
2. a class or abstract with a static `fromHxx` method.
3. a class or abstract with a public constructor.

In any case, we have some function (we're considering the constructor a function), that will be called with arguments derived from the attributes and children of the node. It's worth noting that empty attributes are interpreted as `attributeName={true}`.

Regardless of which of the three above categories a function falls into, it must have one of the following three signatures, which determine how it is processed:

1. a single argument that is an anonymous object and has a property named `children`, or marked via `@:child` / `@:children` metadata (having multiple properties meeting this criterium leads to a compiler error): all attributes are used as properties of the anonymous object and the child nodes are used to populate the children property.

   Let's consider the plain function case:

   ```haxe
   function Window(attr:{ title:VirtualDom, children:VirtualDom }):VirtualDom {
     /* do something fancy */
   }

   // Please note that it's not important what `VirtualDom` is. 
   // The example assumes you're using HXX to create some sort of virtual dom structure.
   
   // Here's how you'd use that function:
   hxx('
     <Window title="Look, I made a window!">
       <p>In this window I have some super cool content!</p>
       <button>Not bad!</button>
       <button>This is lame!</button>
     </Window>
   ');

   //And that is roughly equivalent to:
   Window({ 
     title: "Look, I made a window!", 
     children: [
      p({}, ["In this window I have some super cool content!"]),
      button({}, ["Not bad!"]),
      button({}, ["This is lame!"]),
    ]
   });
   ```

   For the sake of completeness, let's consider the case of a class with a static `fromHxx` function, although this time we'll make use of the `@:children` metadata:

   ```haxe
   class Window {
     static public function fromHxx(attr:{ var title:VirtualDom; @:children var content:VirtualDom; }):VirtualDom {
       /* do something fancy */
     }     
   }

   // in which case the HXX gets generated as follows:
   Window.fromHxx({ 
     title: "Look, I made a window!", 
     content: [//because content was marked with `@:children`, it is populated with the tag's children
      p({}, ["In this window I have some super cool content!"]),
      button({}, ["Not bad!"]),
      button({}, ["This is lame!"]),
    ]
   });
   ```

   Or alternatively, we could rely on the constructor:

   ```haxe
   class Window {
     public function new(attr:{ title:VirtualDom, children:VirtualDom }):VirtualDom {
       /* do something fancy */
     }     
   }

   // in which case the HXX gets generated as follows:
   new Window({ 
     title: "Look, I made a window!", 
     children: [
      p({}, ["In this window I have some super cool content!"]),
      button({}, ["Not bad!"]),
      button({}, ["This is lame!"]),
    ]
   });  
   ```

   The choice between plain function, static method and plain constructor will usually be governed by the framework you're using HXX with.

2. exactly two arguments, namely a single argument that is an anonymous object *without* a property named `children` and a second argument: all attributes are used as properties of the anonymous object and the child nodes are used to populate the second argument:

   ```haxe
   // slightly different signature:
   function Window(attr:{ title:VirtualDom }, children:VirtualDom):VirtualDom {
     /* do something fancy */
   }

   // This time, let's make the title more fancy:
   hxx('
     <Window title=${hxx('Look, I made a <strong>window</strong>!')}>
       Whatever ...
     </Window>
   ');

   // Which winds up like so:
   Window({ title: hxx('Look, I made a <strong>window</strong>!') }, [
     "Whatever ..."
   ]);
   ```

3. a single argument that is an anonymous object *without* a property named `children`: all attributes and child nodes are used to populate the properties of that anonymous object. You may have noticed that in the example before, making a complex title was relatively awkward. This notation is meant for the case where you wish to pass more complex content as arguments without much ASCII art. You can also think of it as *named children* as opposed to the previous notation, where all children are just put together without differentiation. The notation is called:

### Complex attributes

Going back to the example above, we could do the following:

```haxe
// slightly different signature:
function Window(attr:{ title:VirtualDom, content:VirtualDom }):VirtualDom {
  /* do something fancy */
}

// This time, let's make the title more fancy:
hxx('
  <Window>
    <title>
      Look, I made a <strong>window</strong>!
    </title>
    <content>
      <p>In this window I have some super cool content!</p>
      <button>Not bad!</button>
      <button>This is lame!</button>      
    </content>
  </Window>
');

// And it will be transformed to the following Haxe code:
Window({ 
  title: [
    'Look, I made a ',
    strong({}, ['window']),
    '!',
  ],
  content: [
    p({}, ["In this window I have some super cool content!"]),
    button({}, ["Not bad!"]),
    button({}, ["This is lame!"]),
  ]
]);
```

Not relying on complex attributes, you could write this:

```haxe
hxx('  
  <Window
    title=${hxx('
      Look, I made a <strong>window</strong>!
    ')}
    content=${hxx('
      <p>In this window I have some super cool content!</p>
      <button>Not bad!</button>
      <button>This is lame!</button>      
    ')}
  />
');
```

It is fully up to you to decide which notation you find easier to read.

#### Complex function attributes

If a complex attribute is expects a function, then a little extra sugar is applied. Consider the following contrived list rendering utility:

```haxe
function List<T>({ data:Array<T>, render:T->VirtualDom}):VirtualDom
  return hxx('
    <ul>
      <for ${item in data}>
        <li>{render(item)}</li>
      </for>
    </ul>
  ');
```

You can specify a function as a complex argument and thus purely as a tag like so:

1. By declaring the function's arguments as empty attributes, e.g.

   ```haxe
   hxx('
     <List data={cities}>
       <render city>
         <h1>{city.name} <small>(city.country)</small></h1>
         <p>
           Population: {city.population}
         </p>
       </render>
     </List>
   ');

   // this translates to:

   List({
     data: cities,
     render: function (city) return [
       h1({}, [city.name, ' ', small({}, [city.country])])
       p1({}, ['Population: ', city.population])
     ]
   });
   ```

2. If there is only one argument which you leave unnamed, then it gets interpreted in a special way:

   1. if the argument is an object, its properties become directly accessible from the function body, e.g.:

      ```haxe
      hxx('
        <List data={cities}>
          <render>
            <h1>{name} <small>(country)</small></h1>
            <p>
              Population: {population}
            </p>
          </render>
        </List>
      ');

      // this translates to:

      List({
        data: cities,
        render: function (__data__) {

          var name = __data__.name,
              country = __data__.country,
              populatoin = __data__.population;

          return [
            h1({}, [name, ' ', small({}, [country])])
            p1({}, ['Population: ', population])
          ]
        }
      });  
      ```

   2. The argument becomes the implicit switch target in the function body. This is particularly useful for enums. Let's take an example from the manual:

      ```haxe
      enum Color {
        Red;
        Green;
        Blue;
        Rgb(r:Int, g:Int, b:Int);
      }

      // Now let's render a list of such colors:

      hxx('
        <List data={colors}>
          <render>
            <switch>
              <case {Red}> 
                red
              <case {Green}> 
                green
              <case {Blue}> 
                blue
              <case {Rgb(_, _, _)}>
                mixed color
            </switch>
          </render>
        </List>
      ');

      // this is equivalent to

      List({
        data: cities,
        render: function (__data__) return switch __data__ {
          case Red:
            'red'
          case Green:
            'green'
          case Blue:
            'blue'
          case Rgb(_, _, _):
            'mixed color'
        }
      });        
      ```

      Nothing is to stop you from writing `<render color><switch {color}> ... </switch></render>` if you find it easier to read. The syntax exists merely to avoid forcing you to pick names for a value that you intend to decompose anyway.

## Spread operator `...`

HXX supports the spread operator in various places, to tackle the kind of problems that the [ES6 spread operator](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Spread_syntax#Spread_in_object_literals) addresses [in JSX in particular](https://reactjs.org/docs/jsx-in-depth.html#spread-attributes).

### Attribute Spread
  
The spread operator can be used for attributes, e.g. `<someTag {...properties} />`. In this case it works very similarly to its JSX counterpart, but it is backed by [tink_anon's merging](https://github.com/haxetink/tink_anon#merge), which does the object composition at compile time.

There rules are as follows:

- any explicit attribute is used as is
- for any object that is spread onto a tag, all attributes that do not have a value yet are "extracted" from that object, if it is known to define them (at compile time)
- any attributes that were neither explicitly declared or extracted from a spread operation are reported as missing, unless they're optional.

Let's slightly expand the `Window` example above:

```haxe
function Window(attr:{ title:VirtualDom, content:VirtualDom, ?modal:Bool }):VirtualDom {
  /* do something fancy */
}

var fancy = {
  title: 'fancy window',
}
hxx('<Window {...fancy} modal />');//will fail saying that `content` is missing
hxx('<Window {...fancy} content="Yeah!" />');
var boring = {
  title: 'boring window',
  content: 'this is sooooooo boring',
}
hxx('<Window {...boring} {...fancy} />');//will take both `title` and `content` from `boring`, because it comes first
hxx('<Window {...fancy} {...boring} />');//will take `title` from `fancy` and `content` from `boring`
hxx('<Window {...fancy} {...boring} title="Important!" />');//will use "Important!" as `title` (because explicit attributes always take precedence) and `content` from `boring`
```

### Child Spread

Not all structures created from JSX treat arrays of nodes and single nodes alike - for reasons of performance or type safety. Just like Reason ML's JSX flavor, HXX supports child spreads to deal with that. Consider the following example:

```haxe
var poem = [
  hxx('<p>Roses are read</p>'),
  hxx('<p>Violets are blue</p>'),
];

hxx('
  <div>
    <header />
    {poem}
    <footer />
  </div>
');

// this translates to:

div({}, [
  header({})
  poem,
  footer({})
])
```

Now you may notice that the children of the div are an array that is partially double nested (i.e. `[tag, [tag, tag], tag]`). To avoid such mixed nesting and enforce a single level, you can (and usually have to) use the child spread operator:

```haxe
hxx('
  <div>
    <header />
    {...poem}
    <footer />
  </div>
');

// this is pretty much equivalent to:

hxx('
  <div>
    <header />
    <for {line in poem}>{line}</for>
    <footer />
  </div>
');
```

The lines are added as children individually and we thus have no array nesting.

### Spreading into `<let>`

You may also use the spread operator with `<let>`. Say we have:

```haxe
var fooObj = {
  foo: 'foo',
  onfoo: function () trace('foo!'),
}
var barObj = {
  bar: 'bar',
  onbar: function () trace('bar!'),
}
```

Then this will work:

```haxe
hxx('
  <let {...fooObj} {...barObj} blub="blub">
    <button onclick={onfoo}>{foo}</button>
    <button onclick={onbar}>{bar}</button>
    <button>{blub}</button>
  </let>
');
```

## Implicit function syntax

For attributes that are functions with 0 or 1 argument, you may write the function body directly:

```haxe
hxx('
  <button onclick={trace("yeah!")}>Click me!</button>
  <input type="checkbox" onchange={trace(event.currentTarget.checked)} />
');
```

Note that if there's exactly one argument, it will be called "event".

## Whitespace

The treatment of whitespace depends on whether the generated structure even has any notion of whitespace or not. All HXX flavours can rely on `tink.hxx.Generator.trimString` which handles whitespace in a manner that is quite consistent with JSX:
  
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
