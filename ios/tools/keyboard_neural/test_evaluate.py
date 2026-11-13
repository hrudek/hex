"""Stdlib tests run with python3 -I -m unittest discover -s this_directory."""
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('spike', Path(__file__).with_name('evaluate.py'))
spike = importlib.util.module_from_spec(spec)
spec.loader.exec_module(spike)


class SpikeTests(unittest.TestCase):
    def test_unicode_and_barriers(self):
        self.assertEqual(list(spike.events(['Ärger', 'groß', None, 'ENGLISH'])),
                         [('<s>', '<s>', 'ärger'), ('<s>', 'ärger', 'groß'), ('<s>', '<s>', 'english')])

    def test_nfc_not_casefold(self):
        self.assertEqual(list(spike.events(['A\u0308', 'ß']))[-1], ('<s>', 'ä', 'ß'))

    def test_hxn_invalid(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)/'model'
            for raw in (b'', b'HXN1', b'XXXX'+b'\0'*16,
                        struct.pack('<4s4I', b'HXN1', 2**32-1, 128, 1024, 0),
                        struct.pack('<4s4I', b'HXN1', 4, 1, 1, 0)):
                p.write_bytes(raw)
                with self.assertRaises(ValueError): spike.inspect_hxn(p)

    def test_hxn_extent_and_work(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)/'model'
            # Synthetic format-only header; no upstream weights committed.
            v,e,h,s = 4,2,3,0
            size = (20+8*v+s+3)//4*4+4*(2*v+12*h+2*e)+v*e+4*h*(e+h)+e*h
            p.write_bytes(struct.pack('<4s4I', b'HXN1', v,e,h,s)+b'\0'*(size-20))
            info = spike.inspect_hxn(p)
            self.assertEqual(info['mac_step'], 60)
            self.assertEqual(info['mac_cold16'], 974)
            self.assertEqual(info['bytes'], size)

    def test_personal_novel_gate_and_empty_backoff(self):
        corpus = {'a': .4, 'b': .3, 'c': .2, 'd': .1}
        self.assertEqual(spike.personal_top3(corpus, {}), ['a','b','c'])
        self.assertNotIn('novel', spike.personal_top3(corpus, {'novel':1}))
        self.assertEqual(spike.personal_top3(corpus, {'novel':2})[0], 'novel')
        self.assertEqual(spike.personal_top3(corpus, {'d':2})[0], 'd')

    def test_process_measurement_success(self):
        result = subprocess.run([sys.executable, '-I', str(Path(__file__).with_name('measure.py')),
                                 sys.executable, '-I', '-c', 'print("child")'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('child', result.stdout)
        self.assertIn('EVAL R2_10_process peak_rss_kib=', result.stdout)

    def test_process_measurement_propagates_failure(self):
        result = subprocess.run([sys.executable, '-I', str(Path(__file__).with_name('measure.py')),
                                 sys.executable, '-I', '-c', 'raise SystemExit(7)'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 7)

    def test_quantized_zero_and_forward(self):
        try: import numpy as np
        except ImportError: self.skipTest('optional NumPy training dependency not installed')
        q,s = spike.quantize(np.zeros((4,16),dtype='float32'), np)
        self.assertTrue((q==0).all()); self.assertTrue((s>0).all())
        matrices = [np.ones((4,16),dtype='float32')*.5,
                    np.ones((32,32),dtype='float32')*.5,
                    np.ones((4,32),dtype='float32')*.5]
        biases = [np.zeros(32),np.zeros(4)]
        with tempfile.TemporaryDirectory() as d:
            decoded,info = spike.write_model(Path(d)/'model',matrices,biases,np)
            got = spike.forward(np.array([[1,2]]),decoded,biases,np)
            self.assertTrue(np.array_equal(got,[[128]*4]))
            self.assertEqual(info['macs'],1152)
            self.assertEqual(info['float_workspace_bytes'],272)


if __name__ == '__main__': unittest.main()
