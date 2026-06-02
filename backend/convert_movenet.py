#!/usr/bin/env python3
"""
Convert MoveNet SinglePose Lightning → CoreML (.mlmodel)
========================================================
Jalankan sekali saja:
    pip install tensorflow tensorflow-hub coremltools
    python convert_movenet.py

Output: MoveNetLightning.mlmodel (drag ke Xcode project)

MoveNet output shape: [1, 1, 17, 3]
  - 17 keypoints
  - setiap keypoint: [y, x, confidence]  (normalized 0–1)

Urutan 17 keypoint:
  0  nose          5  left_shoulder   10 right_wrist
  1  left_eye      6  right_shoulder  11 left_hip
  2  right_eye     7  left_elbow      12 right_hip
  3  left_ear      8  right_elbow     13 left_knee
  4  right_ear     9  left_wrist      14 right_knee
                                      15 left_ankle
                                      16 right_ankle
"""

import os
import ssl
import urllib.request

os.environ["TF_CPP_MIN_LOG_LEVEL"] = "3"
os.environ["PYTHONHTTPSVERIFY"]    = "0"
os.environ["CURL_CA_BUNDLE"]       = ""
os.environ["REQUESTS_CA_BUNDLE"]   = ""

# Patch SSL globally sebelum import apapun
ssl._create_default_https_context = ssl._create_unverified_context

# Patch urllib opener juga
https_handler = urllib.request.HTTPSHandler(
    context=ssl._create_unverified_context()
)
opener = urllib.request.build_opener(https_handler)
urllib.request.install_opener(opener)

import numpy as np

try:
    import tensorflow as tf
    import tensorflow_hub as hub
    import coremltools as ct
except ImportError as e:
    print(f"❌ Missing package: {e}")
    print("Jalankan: pip install tensorflow tensorflow-hub coremltools")
    exit(1)

print("⏳ Loading MoveNet SinglePose Lightning dari TF Hub...")
print("   (pertama kali bisa 1-2 menit karena download ~12MB)\n")

model_url = "https://tfhub.dev/google/movenet/singlepose/lightning/4"
hub_model  = hub.load(model_url)
infer      = hub_model.signatures["serving_default"]

# Wrap ke tf.function agar bisa di-trace oleh coremltools
@tf.function(input_signature=[tf.TensorSpec(shape=[1, 192, 192, 3], dtype=tf.int32)])
def predict(image):
    return infer(image)["output_0"]

print("⏳ Menyimpan SavedModel sementara...")
saved_model_path = "/tmp/movenet_saved"

# Bungkus predict sebagai Module agar bisa disimpan dengan signature
class MoveNetModule(tf.Module):
    def __init__(self, model):
        super().__init__()
        self._model = model

    @tf.function(input_signature=[tf.TensorSpec([1, 192, 192, 3], tf.int32)])
    def predict(self, image):
        return self._model.signatures["serving_default"](image)

module = MoveNetModule(hub_model)
tf.saved_model.save(module, saved_model_path,
                    signatures={"serving_default": module.predict})

# Cek output keys yang tersedia
loaded    = tf.saved_model.load(saved_model_path)
sig       = loaded.signatures["serving_default"]
out_keys  = list(sig.structured_outputs.keys())
print(f"   Output keys: {out_keys}")

print("⏳ Converting SavedModel ke CoreML...\n")
mlmodel = ct.convert(
    saved_model_path,
    source="tensorflow",
    inputs=[ct.TensorType(
        name  = "image",
        shape = (1, 192, 192, 3),
        dtype = np.int32
    )],
)

# Metadata
mlmodel.short_description = "MoveNet SinglePose Lightning — 17 body keypoints (Google)"

output_path = "MoveNetLightning.mlpackage"
mlmodel.save(output_path)

print(f"✅ Berhasil! File disimpan: {output_path}")
print(f"   Ukuran: {os.path.getsize(output_path) / 1024 / 1024:.1f} MB")
print("\n📱 Langkah selanjutnya:")
print("   1. Drag MoveNetLightning.mlmodel ke Xcode project")
print("   2. Centang target 'arko-fitnesscoach'")
print("   3. Jalankan aplikasi — FormCheckView akan pakai model ini")
