# Changelog for B9

## 0.5.62

* Rewrite `B9.Shake.SharedImageRules` in line with 
  Shake's example for custom rules  

* Replace `ConcatableSyntax` by using `Binary` instances

* Add a newtype wrapper around `YamlObject` for **cloud-init** yaml documents
  `CloudConfigYaml`
  
  This new type serves the purpose of add the `#cloud-config`
  line to the top of the generated yaml document, 
  as [required by cloud-init](https://cloudinit.readthedocs.io/en/latest/topics/format.html#cloud-config-data).
  
  The `Binary` instance adds this **header line** and 
  delegates the rendering of the yaml document to 
  `YamlObject`.
  
* Remove the rendering of this header line in the `YamlObject` 
  `Binary` instance.

* Rename `RenderYaml` to `RenderYamlObject` In order to prevent unexpected 
  runtime behaviour in code that uses this library.
  
* Introduce the type `Environment` that replaces the ubiquotus `[(String, String)]`
  by a lazy `Text` based `HashMap`.
  
* Rename the previous `B9.Content.Generator` to `B9.Content.Builtin`

* Introduce `ContentGenerator` as an open, extensible alternative
  to `Content`, `AST` and `CanRender` in the module
  `B9.Content.Generator`

* Move `CanRender` from `B9.Content.AST` to `B9.Content.Generator`    

* Switch to lazy `Text`s and `ByteString`s where possible, since B9 might
  read/generate large files. 
  
* Rename `CanRender` to `ToContentGenerator` 
  and change the method signatur to return the new `ContentGenerator` type  

* Fix spelling: Rename B9Invokation to B9Invocation
  
* Rename `FromAST` to `FromAST`