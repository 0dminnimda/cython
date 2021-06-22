import shutil
import os
import tempfile

import Cython.Build.Dependencies
import Cython.Utils
from Cython.TestUtils import CythonTest



SAME = "The result of cytonization is the same"
INCORRECT = "Incorrect cythonization"
LINE_BEFORE_IMPLEMENTATION = '  /* "{filename}":{at_line}\n'
VARS_LINE = '  /*--- Wrapped vars code ---*/\n'


class TestRecythonize(CythonTest):
    language_level = 3
    dep_tree = Cython.Build.Dependencies.create_dependency_tree()

    def сlear_function_and_Dependencies_caches(self):
        Cython.Utils.clear_function_caches()
        Cython.Build.Dependencies._dep_tree = None  # discard method caches

    def setUp(self):
        CythonTest.setUp(self)
        self.сlear_function_and_Dependencies_caches()
        self.temp_dir = (
            tempfile.mkdtemp(
                prefix='recythonize-test',
                dir='TEST_TMP' if os.path.isdir('TEST_TMP') else None
            )
        )
        self.src_dir = os.path.join(self.temp_dir, 'src')
        os.mkdir(self.src_dir)  # self.temp_dir is already a temp

    def tearDown(self):
        CythonTest.tearDown(self)
        self.сlear_function_and_Dependencies_caches()
        shutil.rmtree(self.temp_dir)

    def fresh_cythonize(self, *args, **kwargs):
        self.сlear_function_and_Dependencies_caches()
        kwargs.update(language_level=self.language_level)
        Cython.Build.Dependencies.cythonize(*args, **kwargs)

    def refresh_dep_tree(self):
        Cython.Utils.clear_function_caches()
        Cython.Utils.clear_method_caches(self.dep_tree)
        self.dep_tree._transitive_cache.clear()

    def fresh_all_dependencies(self, *args, **kwargs):
        self.refresh_dep_tree()
        return self.dep_tree.all_dependencies(*args, **kwargs)

    def relative_lines(self, lines, line, start, end):
        try:
            ind = lines.index(line)
            return lines[ind+start: ind+end]
        except ValueError:
            # XXX: It is assumed that VARS_LINE is always present.
            ind = lines.index(VARS_LINE)
            raise ValueError(
                "{0!r} was not found, presumably in {1}".format(
                    line, lines[ind-10: ind-1]))
        except Exception as e:
            raise e

    def relative_lines_from_file(self, path, line, start, end, join=True):
        with open(path) as f:
            lines = f.readlines()

        lines = self.relative_lines(lines, line, start, end)
        if join:
            return "".join(lines)
        return lines

    def recythonize_on_pxd_change(self, ext, pxd_exists_for_first_check):
        source_filename = 'a' + ext
        
        pxd_to_be_modified = os.path.join(self.src_dir, 'a.pxd')
        source = os.path.join(self.src_dir, source_filename)
        generated_c = os.path.join(self.src_dir, 'a.c')  # should change

        source_line_1 = LINE_BEFORE_IMPLEMENTATION.format(
            filename=source_filename, at_line=1)

        if pxd_exists_for_first_check:
            with open(pxd_to_be_modified, 'w') as f:
                f.write('cdef int x\n')

        with open(source, 'w') as f:
            f.write('x = 1\n')

        dependencies = self.fresh_all_dependencies(source)
        self.assertIn(source, dependencies)
        if pxd_exists_for_first_check:
            self.assertIn(pxd_to_be_modified, dependencies)
            self.assertEqual(2, len(dependencies))
        else:
            self.assertEqual(1, len(dependencies))

        # Create a.c
        self.fresh_cythonize(source)

        definition_before = self.relative_lines_from_file(
            generated_c, source_line_1, 0, 7)

        if pxd_exists_for_first_check:
            self.assertIn("a_x = 1;", definition_before, INCORRECT)
        else:
            self.assertNotIn("a_x = 1;", definition_before, INCORRECT)

        with open(pxd_to_be_modified, 'w') as f:
            f.write('cdef float x\n')

        # otherwise nothing changes since there are no new files
        if not pxd_exists_for_first_check:
            dependencies = self.fresh_all_dependencies(source)
            self.assertIn(source, dependencies)
            self.assertIn(pxd_to_be_modified, dependencies)
            self.assertEqual(2, len(dependencies))

        # Change a.c
        self.fresh_cythonize(source)

        definition_after = self.relative_lines_from_file(
            generated_c, source_line_1, 0, 7)

        self.assertNotIn("a_x = 1;", definition_after, SAME)
        self.assertIn("a_x = 1.0;", definition_after, INCORRECT)

    # pxd_exists_for_first_check is not used because cimport requires pxd
    # to import another script.
    def recythonize_on_dep_pxd_change(self, ext_a, ext_b):
        dep_filename, source_filename = "a" + ext_a, "b" + ext_b

        pxd_to_be_modified = os.path.join(self.src_dir, 'a.pxd')
        source_dependency = os.path.join(self.src_dir, dep_filename)
        c_generated_from_dep = os.path.join(self.src_dir, 'a.c')  # should change
        pxd_for_cimport = os.path.join(self.src_dir, 'b.pxd')
        source = os.path.join(self.src_dir, source_filename)
        c_generated_from_source = os.path.join(self.src_dir, 'b.c')  # should change

        dep_line_1 = LINE_BEFORE_IMPLEMENTATION.format(
            filename=dep_filename, at_line=1)
        source_line_1 = LINE_BEFORE_IMPLEMENTATION.format(
            filename=source_filename, at_line=1)

        with open(pxd_to_be_modified, 'w') as f:
            f.write('cdef int x\n')

        with open(source_dependency, 'w') as f:
            f.write('x = 1\n')

        with open(pxd_for_cimport, 'w') as f:
            f.write('cimport a\n')

        with open(source, 'w') as f:
            f.write('a.x = 2\n')

        dependencies = self.fresh_all_dependencies(source)
        self.assertIn(pxd_for_cimport, dependencies)
        self.assertIn(source, dependencies)
        self.assertIn(pxd_to_be_modified, dependencies)
        self.assertEqual(3, len(dependencies))

        # Create a.c and b.c
        self.fresh_cythonize([source_dependency, source])

        dep_definition_before = self.relative_lines_from_file(
            c_generated_from_dep, dep_line_1, 0, 7)

        source_definition_before = self.relative_lines_from_file(
            c_generated_from_source, source_line_1, 0, 7)

        self.assertIn("a_x = 1;", dep_definition_before, INCORRECT)
        self.assertIn("a_x = 2;", source_definition_before, INCORRECT)

        with open(pxd_to_be_modified, 'w') as f:
            f.write('cdef float x\n')

        # Change a.c and b.c
        self.fresh_cythonize([source_dependency, source])

        dep_definition_after = self.relative_lines_from_file(
            c_generated_from_dep, dep_line_1, 0, 7)

        source_definition_after = self.relative_lines_from_file(
            c_generated_from_source, source_line_1, 0, 7)

        self.assertNotIn("a_x = 1;", dep_definition_after, SAME)
        self.assertNotIn("a_x = 2;", source_definition_after, SAME)
        self.assertIn("a_x = 1.0;", dep_definition_after, INCORRECT)
        self.assertIn("a_x = 2.0;", source_definition_after, INCORRECT)

    def test_recythonize_py_on_pxd_change(self):
        self.recythonize_on_pxd_change(".py", pxd_exists_for_first_check=True)

    def test_recythonize_pyx_on_pxd_change(self):
        self.recythonize_on_pxd_change(".pyx", pxd_exists_for_first_check=True)

    def test_recythonize_py_on_pxd_creating(self):
        self.recythonize_on_pxd_change(".py", pxd_exists_for_first_check=False)

    def test_recythonize_pyx_on_pxd_creating(self):
        self.recythonize_on_pxd_change(".pyx", pxd_exists_for_first_check=False)

    def test_recythonize_py_py_on_dep_pxd_change(self):
        self.recythonize_on_dep_pxd_change(".py", ".py")

    def test_recythonize_py_pyx_on_dep_pxd_change(self):
        self.recythonize_on_dep_pxd_change(".py", ".pyx")

    def test_recythonize_pyx_py_on_dep_pxd_change(self):
        self.recythonize_on_dep_pxd_change(".pyx", ".py")

    def test_recythonize_pyx_pyx_on_dep_pxd_change(self):
        self.recythonize_on_dep_pxd_change(".pyx", ".pyx")

