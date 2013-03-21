XMLElement
==========

XMLElement is a read only xml parser that uses libxml2 for the heavy lifting, and provides convenient access to the elements, attributes, and cdata of xml documents

To use XMLElement you must include XMLElement.* in your project and link to xmllib2.dylib. You must also add "$(SDK_DIR)"/usr/include/libxml2 to the Header Search Paths in Build Settings and set it to recursive.

Status
======

Functional but limited. No namespace support. Will likely never have modification and write support. No validation. The goal of this library is to strictly parse xml from APIs and other sources that should be generating solid xml.

Todo
====

- Test suite
- Namespace support
