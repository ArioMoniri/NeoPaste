import os

# Define the license header
LICENSE_HEADER = """//
// Copyright 2025 Ariorad Moniri
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
"""

# Check and add the license header to .swift files
for root, dirs, files in os.walk("."):
    for file in files:
        if file.endswith(".swift"):
            filepath = os.path.join(root, file)

            with open(filepath, "r") as f:
                content = f.read()

            # Check if the license header is already present
            if LICENSE_HEADER.strip() not in content:
                print(f"Adding license to {filepath}")
                with open(filepath, "w") as f:
                    f.write(LICENSE_HEADER + "\n" + content)
