/*
 * Copyright 2004-2019 Cray Inc.
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
  .. note:: 

    This package relies on Chapel ``extern`` code blocks and so requires that
    ``CHPL_LLVM=llvm`` or ``CHPL_LLVM=system`` and that the Chapel compiler is
    built with LLVM enabled. As well, currently only ``CHPL_TARGET_ARCH=x86_64``
    is supported as we make use of the x86-64 instruction: CMPXCHG16B_.

    .. _CMPXCHG16B: https://www.felixcloutier.com/x86/cmpxchg8b:cmpxchg16b
    
  This module provides support for performing atomic operations on pointers
  to  ``unmanaged`` classes, which can be thought of as building blocks for
  creating non-blocking algorithms and data structures.

  .. note::

    Only ``unmanaged`` classes are supported as they are represented, internally,
    as raw 64-bit or 128-bit pointers. We do not support ``shared`` or ``owned``
    objects as they are essentially wrappers around an ``unmanaged`` object, and
    ``borrowed`` objects require a static lifetime.

  .. warning::

    Currently, ``AtomicObject`` only supports up to 65535 locales, and also works on
    the assumption that only the lowest 48 bits of the virtual address space will ever
    be used. An exascale solution that allows for an arbitrary number of compute nodes
    and for the entire 64-bit address space to be utilized is future work that is in-progress.

  ABA Wrapper
  -----------

  .. note::

    We ``forward`` all accesses to the ``ABA`` wrapper to the object it is wrapping 
    so that whether or not the ABA versions of the ``AtomicObject`` API is used, it
    becomes as transparent as possible. This applies to all method and field accesses.
    As forwarding does not apply to operators, common operators are explicitly defined
    in such a way that they will also be forwarded to the object being wrapped.


*/
module AtomicObjects {

  if CHPL_TARGET_ARCH != "x86_64" {
    compilerWarning("The AtomicObjects package module cannot support CHPL_TARGET_ARCH=", CHPL_TARGET_ARCH, ", only x86_64 is supported.");
  }

  // Declaration of ``CMPXCHG16B`` primitives.
  extern {
    #include <stdint.h>
    #include <stdio.h>
    #include <stdlib.h>

    struct uint128 {
      uint64_t lo;
      uint64_t hi;
    };

    typedef struct uint128 uint128_t;
    static inline int cas128bit(void *srcvp, void *cmpvp, void *withvp) {
      uint128_t __attribute__ ((aligned (16))) cmp_val = * (uint128_t *) cmpvp;
      uint128_t __attribute__ ((aligned (16))) with_val = * (uint128_t *) withvp;      
      uint128_t *src = srcvp;
      uint128_t *cmp = &cmp_val;
      uint128_t *with = &with_val;
      char result;

      __asm__ __volatile__ ("lock; cmpxchg16b (%6);"
          "setz %7; "
          : "=a" (cmp->lo),
          "=d" (cmp->hi)
          : "0" (cmp->lo),
          "1" (cmp->hi),
          "b" (with->lo),
          "c" (with->hi),
          "r" (src),
          "m" (result)
          : "cc", "memory");
      *(uint128_t *) cmpvp = cmp_val;
      return result;
    }

    static inline void write128bit(void *srcvp, void *valvp) {
      uint128_t __attribute__ ((aligned (16))) with_val = * (uint128_t *) valvp;
      uint128_t __attribute__ ((aligned (16))) cmp_val = * (uint128_t *) srcvp;
      uint128_t *src = srcvp;
      uint128_t *cmp = &cmp_val;
      uint128_t *with = &with_val;
      char successful = 0;

      while (!successful) {
        __asm__ __volatile__ ("lock; cmpxchg16b (%6);"
            "setz %7; "
            : "=a" (cmp->lo),
            "=d" (cmp->hi)
            : "0" (cmp->lo),
            "1" (cmp->hi),
            "b" (with->lo),
            "c" (with->hi),
            "r" (src),
            "m" (successful)
            : "cc", "memory");
      }
    }

    static inline void read128bit(void *srcvp, void *dstvp) {
      uint128_t __attribute__ ((aligned (16))) src_val = * (uint128_t *) srcvp;
      uint128_t __attribute__ ((aligned (16))) cmp_val = src_val;
      uint128_t __attribute__ ((aligned (16))) with_val = src_val;
      uint128_t *src = srcvp;
      uint128_t *cmp = &cmp_val;
      uint128_t *with = &with_val;
      char result;

      __asm__ __volatile__ ("lock; cmpxchg16b (%6);"
          "setz %7; "
          : "=a" (cmp->lo),
          "=d" (cmp->hi)
          : "0" (cmp->lo),
          "1" (cmp->hi),
          "b" (with->lo),
          "c" (with->hi),
          "r" (src),
          "m" (result)
          : "cc", "memory");

      *(uint128_t *)dstvp = cmp_val;
    }
  }

  pragma "no doc"
  extern type atomic_uint_least64_t;

  pragma "no doc"
  extern type wide_ptr_t;

  pragma "no doc"
  extern type c_nodeid_t;

  pragma "no doc"
  extern proc chpl_return_wide_ptr_node(c_nodeid_t, c_void_ptr) : wide_ptr_t;

  /*
     Constants used for managing compression and decompression for atomic objects. 
     It should be noted that if numLocales >= 2^16, then any
     object being operated on is added to the descriptor table, which will leak data
     if never freed with '_delete' (although if the memory is reused,
     so will the memory managed by this object). The descriptor table will be cleaned
     up automatically when this goes out of scope.
  */

  if numLocales >= 2**16 {
    writeln("[WARNING]: AtomicObjects currently only supports up to 65535 locales!");
  }

  pragma "no doc"
  param compressedAddrMask = 0x0000FFFFFFFFFFFF;
  pragma "no doc"
  param compressedLocaleIdMask = 0xFFFF;
  pragma "no doc"
  param tableLocaleIdMask = 0xFFFFFFFF;
  pragma "no doc"
  param tableIdxMask = 0xFFFFFFFF;
  pragma "no doc"
  param compressedLocIdOffset = 48;

  pragma "no doc"
  inline proc castToObj(type objType, addr) {
    return __primitive("cast", objType, uintToCVoidPtr(addr));
  }

  pragma "no doc"
  inline proc uintToCVoidPtr(addr) {
    return __primitive("cast", c_void_ptr, addr);
  }

  pragma "no doc"
  // This is busted: $CHPL_HOME/test/optimizations/widepointers/return.future
  inline proc widePointerCheck(obj) {
    if !__primitive("is wide pointer", obj) {
      compilerError(
          "Dummy object created was not a wide pointer!",
          " Assumption: Inside a 'local' block"
          );
    }
  }

  pragma "no doc"
  inline proc getAddrAndLocality(obj) : (locale, uint(64)) {
    return (obj.locale, getAddr(obj));
  }

  pragma "no doc"
  inline proc getAddr(obj) : uint(64) {
    return __primitive("cast", uint(64), __primitive("_wide_get_addr", obj));
  }


  pragma "no doc"
  /*
     Compresses an object into a descriptor.
  */
  proc compress(obj) : uint {
    if obj == nil then return 0;

    // Perform a faster compression by packing the 48 usable bits of the virtual
    // address with 16 bits of the locale/node id.
    var locId : uint(64) = obj.locale.id : uint(64);
    var addr = getAddr(obj);
    return (locId << compressedLocIdOffset) | (addr & compressedAddrMask);
  }

  pragma "no doc"
  /*
     Decompresses a descriptor into the wide pointer object.
  */
  proc decompress(type objType, descr:uint) : objType {
    if descr == 0 then return nil;

    // If we have less than 2^16 locales, then we know we performed the
    // faster compression method so we need to decompress it in the same way...
    var locId = descr >> compressedLocIdOffset;
    var addr = descr & compressedAddrMask;
    if locId == 0 then return castToObj(objType, addr);

    // We've created the wide pointer, but unfortunately Chapel does not support
    // the ability to cast it to the actual object, so we have to do some
    // trickery to get it to work. What we do is we allocate a wide pointer on
    // the stack and memcpy our wideptr into the other. This is needed so we
    // have the same type.
    var wideptr = chpl_return_wide_ptr_node(locId, uintToCVoidPtr(addr));
    var newObj : objType;
    on Locales[here.id] do newObj = nil;
    c_memcpy(c_ptrTo(newObj), c_ptrTo(wideptr), 16);
    return newObj;
  }

  /*
     Wrapper for an object protected by an ABA counter. This type forwards to the object
     represented by its underlying pointer and hence can be used as if it were the object
     itself, via 'forwarding'. This type should not be created by the user, and instead
     should be created by LocalAtomicObject. The object protected by this ABA wrapper can
     be extracted via 'getObject'.
  */
  record ABA {
    type __ABA_objType;
    pragma "no doc"
    var __ABA_obj : __ABA_objType;
    pragma "no doc"
    var __ABA_cnt : uint(64);

    proc init(obj : ?objType, cnt : uint(64)) {
      this.__ABA_objType = objType;
      this.__ABA_obj = obj;
      this.__ABA_cnt = cnt;
    }

    proc init(type objType) {
      this.__ABA_objType = objType;
    }

    proc init=(other : ABA(?objType)) {
      this.__ABA_objType = objType;
      this.__ABA_obj = other.obj;
      this.__ABA_cnt = other.cnt;
    }

    inline proc getObject() {
      return __ABA_obj;
    }

    proc readWriteThis(f) {
      f <~> "(ABA){cnt=" <~> this.__ABA_cnt <~> ", obj=" <~> this.__ABA_obj <~> "}";
    }

    forwarding this.__ABA_obj;
  }

  pragma "no doc"
  record _ABAInternal {
    type objType;
    pragma "no doc"
    var _ABA_ptr : atomic uint(64);
    pragma "no doc"
    var _ABA_cnt : atomic uint(64);

    proc init(type objType, ptr : uint(64), cnt : uint(64)) {
      this.objType = objType;
      this.complete();
      this._ABA_ptr.write(ptr);
      this._ABA_cnt.write(cnt);
    }

    proc init(type objType, ptr : uint(64)) {
      this.objType = objType;
      this.complete();
      this._ABA_ptr.write(ptr);
    }

    proc init(type objType) {
      this.objType = objType;
    }
  }

  /*
    Special case operator that compares two ``ABA`` wrappers.
  */
  proc ==(const ref aba1 : ABA, const ref aba2 : ABA) {
    return aba1.cnt == aba2.cnt && aba1.obj == aba2.obj;
  }

  proc ==(const ref aba : ABA, other) {
    return aba.obj == other;
  }

  proc >(const ref aba : ABA, other) {
    return aba.obj > other;
  }

  proc >=(const ref aba : ABA, other) {
    return aba.obj >= other;
  }

  proc <(const ref aba : ABA, other) {
    return aba.obj < other;
  }

  proc <=(const ref aba : ABA, other) {
    return aba.obj <= other;
  }

  proc +(const ref aba : ABA, other) {
    return aba.obj + other;
  }

  proc -(const ref aba : ABA, other) {
    return aba.obj - other;
  }

  proc *(const ref aba : ABA, other) {
    return aba.obj * other;
  }

  proc /(const ref aba : ABA, other) {
    return aba.obj / other;
  }

  proc +=(const ref aba : ABA, other) {
    aba.obj += other;
  }

  proc -=(const ref aba : ABA, other) {
    aba.obj -= other;
  }

  proc *=(const ref aba : ABA, other) {
    aba.obj *= other;
  }

  proc /=(const ref aba : ABA, other) {
    aba.obj /= other;
  }

  proc ^(const ref aba : ABA, other) {
    return aba.obj ^ other;
  }

  proc |(const ref aba : ABA, other) {
    return aba.obj | other;
  }

  proc ^=(const ref aba : ABA, other) {
    aba.obj ^= other;
  }

  proc |=(const ref aba : ABA, other) {
    aba.obj |= other;
  }

  proc <<(const ref aba : ABA, other) {
    return aba.obj << other;
  }

  proc >>(const ref aba : ABA, other) {
    return aba.obj >> other;
  }

  proc <<=(const ref aba : ABA, other) {
    aba.obj <<= other;
  }

  proc >>=(const ref aba : ABA, other) {
    aba.obj >>= other;
  }

  record AtomicObject {
    type objType;
    // If this atomic instance provides ABA support
    param hasABASupport : bool;
    // If this atomic instance provides global atomics
    param hasGlobalSupport : bool;
    var atomicVar : if hasABASupport then _ddata(_ABAInternal(objType)) else atomic uint(64);

    proc init(type objType, param hasABASupport = false, param hasGlobalSupport = !_local) {
      if !isUnmanagedClass(objType) { 
        compilerError("LocalAtomicObject must take a 'unmanaged' type, not ", objType : string);
      }
      this.objType = objType;
      this.hasABASupport = hasABASupport;
      this.hasGlobalSupport = hasGlobalSupport;
      this.complete();
      if hasABASupport {
        var ptr : c_void_ptr;
        posix_memalign(c_ptrTo(ptr), 16, c_sizeof(ABA(objType)));
        this.atomicVar = ptr:_ddata(_ABAInternal(objType));
        c_memset(ptr, 0, c_sizeof(ABA(objType)));
      }
    }

    proc init(type objType, defaultValue : objType, param hasABASupport = false, param hasGlobalSupport = !_local) {
      init(objType, hasABASupport, hasGlobalSupport);
      var ptr : uint(64);
      if hasGlobalSupport {
        ptr = compress(defaultValue);
      } else {
        ptr = getAddr(defaultValue);
      }
      
      if hasABASupport {
        atomicVar[0]._ABA_ptr.write(ptr);
      } else {
        atomicVar.write(ptr);
      }
    }

    pragma "no doc"
    inline proc atomicVariable ref {
      if hasABASupport {
        return atomicVar[0]._ABA_ptr;
      } else {
        return atomicVar;
      }
    }

    // Object(objType) -> Pointer(uint(64))
    pragma "no doc"
    inline proc toPointer(obj:objType) : uint(64) {
      if hasGlobalSupport {
        return compress(obj);
      } else {
        // Check if an object is non-local when 'hasGlobalSupport' is false
        // Note: Both `_local` and `boundsChecking` are compile-time constants
        // and will compile this away.
        if !_local && boundsChecking {
          localityCheck(obj);
        }
        return getAddr(obj);
      }
    }

    // Pointer(uint(64)) -> Object(objType)
    pragma "no doc"
    inline proc fromPointer(ptr : uint(64)) : objType {
      if hasGlobalSupport {
        return decompress(objType, ptr);
      } else {
        return castToObj(objType, ptr);
      }
    }

    pragma "no doc"
    inline proc localityCheck(objs...) {
      if boundsChecking && (|| reduce [obj in objs] obj.locale != this.locale) then
        halt("Locality check failed on ", for obj in objs do getAddrAndLocality(obj), " when expected to be hosted on ", this.locale);
    }

    // Called from ABA API, which ensures that the ABA API is only called on an
    // AtomicObject which supports data
    pragma "no doc"
    inline proc doABACheck() param {
      if !hasABASupport {
        compilerWarning("Attempt to use ABA API from AtomicObject(hasABASupport=", hasABASupport, ", hasGlobalSupport=", hasGlobalSupport, ")");
      }
    }

    proc readABA() : ABA(objType) {
      doABACheck();
      var ret : ABA(objType);
      on this {
        var dest : ABA(objType);
        read128bit(atomicVar:c_void_ptr, c_ptrTo(dest));
        ret = dest;
      }
      return ret;
    }

    proc read() : objType {
      return fromPointer(atomicVariable.read());
    }

    proc compareExchange(expectedObj : objType, newObj : objType) : bool {
      return atomicVariable.compareExchange(toPointer(expectedObj), toPointer(newObj));
    }

    proc compareExchangeABA(expectedObj : ABA(objType), newObj : objType) : bool {
      doABACheck();
      var ret : bool;
      on this {
        var cmp = expectedObj;
        var val = new ABA(objType, toPointer(newObj), atomicVar[0]._ABA_cnt.read() + 1);
        ret = cas128bit(atomicVar:c_void_ptr, c_ptrTo(cmp), c_ptrTo(val)) : bool;
      }
      return ret;
    }

    proc compareExchangeABA(expectedObj : ABA(objType), newObj : ABA(objType)) : bool {
      compareExchangeABA(expectedObj, newObj.getObject());
    }

    proc write(newObj:objType) {
      atomicVariable.write(toPointer(newObj));
    }

    proc write(newObj:ABA(objType)) {
      write(newObj.getObject());
    }

    proc writeABA(newObj: ABA(objType)) {
      write128bit(atomicVar:c_void_ptr, c_ptrTo(newObj));
    }

    proc writeABA(newObj: objType) {
      doABACheck();
      writeABA(new ABA(objType, toPointer(objType), atomicVar[0]._ABA_cnt.read() + 1));
    }

    inline proc exchange(newObj:objType) {
      return fromPointer(objType, atomicVariable.exchange(toPointer(newObj)));
    }

    proc readWriteThis(f) {
      f <~> atomicVariable.read();
    }
  }
}
