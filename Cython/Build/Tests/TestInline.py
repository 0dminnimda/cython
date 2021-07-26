import os
import tempfile
import unittest
from Cython.Shadow import inline
from Cython.Build.Inline import safe_type
from Cython.TestUtils import CythonTest

try:
    import numpy
    has_numpy = True
except:
    has_numpy = False

test_kwds = dict(force=True, quiet=True)

global_value = 100

class TestInline(CythonTest):
    def setUp(self):
        CythonTest.setUp(self)
        self.test_kwds = dict(test_kwds)
        if os.path.isdir('TEST_TMP'):
            lib_dir = os.path.join('TEST_TMP','inline')
        else:
            lib_dir = tempfile.mkdtemp(prefix='cython_inline_')
        self.test_kwds['lib_dir'] = lib_dir

    def test_simple(self):
        self.assertEqual(inline("return 1+2", **self.test_kwds), 3)  # f

    def test_types(self):
        self.assertEqual(inline("""  # f
            cimport cython
            return cython.typeof(a), cython.typeof(b)
        """, a=1.0, b=[], **self.test_kwds), ('double', 'list object'))

    def test_locals(self):
        a = 1
        b = 2
        self.assertEqual(inline("return a+b", **self.test_kwds), 3)  # f

    def test_globals(self):
        self.assertEqual(inline("return global_value + 1", **self.test_kwds), global_value + 1)  # f

    def test_no_return(self):
        self.assertEqual(inline("""  # f
            a = 1
            cdef double b = 2
            cdef c = []
        """, **self.test_kwds), dict(a=1, b=2.0, c=[]))

    def test_def_node(self):
        foo = inline("def foo(x): return x * x", **self.test_kwds)['foo']  # f
        self.assertEqual(foo(7), 49)

    def test_class_ref(self):
        class Type(object):
            pass
        tp = inline("Type")['Type']
        self.assertEqual(tp, Type)

    def test_pure(self):
        import cython as cy
        b = inline("""  # f
        b = cy.declare(float, a)
        c = cy.declare(cy.pointer(cy.float), &b)
        return b
        """, a=3, **self.test_kwds)
        self.assertEqual(type(b), float)

    def test_compiler_directives(self):
        self.assertEqual(
            inline('return sum(x)',
                   x=[1, 2, 3],
                   cython_compiler_directives={'boundscheck': False}),
            6
        )

    def test_lang_version(self):
        # GH-3419. Caching for inline code didn't always respect compiler directives.
        inline_divcode = "def f(int a, int b): return a/b"
        self.assertEqual(
            inline(inline_divcode, language_level=2)['f'](5,2),
            2
        )
        self.assertEqual(
            inline(inline_divcode, language_level=3)['f'](5,2),
            2.5
        )
        self.assertEqual(
            inline(inline_divcode, language_level=2)['f'](5,2),
            2
        )

    def test_repeated_use(self):
        inline_mulcode = "def f(int a, int b): return a * b"
        self.assertEqual(inline(inline_mulcode)['f'](5, 2), 10)
        self.assertEqual(inline(inline_mulcode)['f'](5, 3), 15)
        self.assertEqual(inline(inline_mulcode)['f'](6, 2), 12)
        self.assertEqual(inline(inline_mulcode)['f'](5, 2), 10)

        f = inline(inline_mulcode)['f']
        self.assertEqual(f(5, 2), 10)
        self.assertEqual(f(5, 3), 15)

    @unittest.skipIf(not has_numpy, "NumPy is not available")
    def test_numpy(self):
        import numpy
        a = numpy.ndarray((10, 20))
        a[0,0] = 10
        self.assertEqual(safe_type(a), 'numpy.ndarray[numpy.float64_t, ndim=2]')
        self.assertEqual(inline("return a[0,0]", a=a, **self.test_kwds), 10.0)
