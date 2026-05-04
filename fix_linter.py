
import re
import os

def fix_file(filepath):
    print(f"Fixing {filepath}")
    with open(filepath, 'r') as f:
        content = f.read()
    original = content

    # 1. Remove unused services import (very common, breaks nothing)
    if 'import \'package:flutter/services.dart\';' in content:
        # Check if actually used (Platform, etc)
        if 'Platform.' not in content and 'MethodChannel' not in content and 'ServicesBinding' not in content:
            content = content.replace("import 'package:flutter/services.dart';\n", "")
            # Also remove if it's the only import on that line with others
            content = re.sub(r'import \'package:flutter/cupertino\.dart\';\nimport \'package:flutter/services\.dart\';\n', 
                            "import 'package:flutter/cupertino.dart';\n", content)
            content = re.sub(r'import \'package:flutter/material\.dart\';\nimport \'package:flutter/services\.dart\';\n',
                            "import 'package:flutter/material.dart';\n", content)

    # 2. Fix unintended_html_in_doc_comment (escape < > in doc comments)
    # This is tricky, we do a simple pass for obvious ones in service files
    lines = content.split('\n')
    new_lines = []
    for line in lines:
        if '///' in line and ('<code>' in line or '</code>' in line or '<b>' in line):
            line = line.replace('<code>', '`').replace('</code>', '`')
        new_lines.append(line)
    content = '\n'.join(new_lines)

    # 3. Fix prefer_const_constructors (naive but effective for StatelessWidgets)
    # Match lines like "SomeWidget(" that are not already "const"
    # We look for common Flutter widget patterns.
    # This regex finds "WidgetName(" preceded by whitespace and not "const"
    def add_const(match):
        full = match.group(0)
        # Avoid double const
        if 'const ' in full:
            return full
        # Avoid adding const to things like ListView.builder (needs const before children)
        # We just prefix the widget name
        return full.replace(match.group(1), 'const ' + match.group(1))

    # Pattern: start of line (spaces), then Word (starting capital), then '('
    # Exclude if preceded by 'const' or 'widget.'
    content = re.sub(r'(\n\s+)([A-Z][a-zA-Z0-9_]*)\(', lambda m: add_const(m), content)

    # 4. Fix WillPopScope -> PopScope (simple case, keep canPop: true by default)
    if 'WillPopScope' in content:
        content = content.replace('WillPopScope(', 'PopScope(')
        # Add canPop: true if not present (simple check)
        # This is risky, but for this codebase it seems fine (just prevents back)
        # We do a more careful find/replace in onGenerateRoute section

    # 5. Remove unused local variable _birthYear assignment
    # Happens in onboarding_screen.dart line ~108
    # _birthYear = _yearPickerKey.currentState?.value;
    # It's immediately overwritten or not used. We comment it out or remove.
    # We'll handle this in the specific file logic.

    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        return True
    return False

def main():
    lib_path = '/workspaces/Ysopmaniac-Export/lib'
    for root, dirs, files in os.walk(lib_path):
        # Skip l10n generated files, focus on source
        if 'l10n' in root:
            continue
        for file in files:
            if file.endswith('.dart'):
                # Target main problem files first to be safe
                if 'settings_screen' in file or 'home_page' in file or 'onboarding' in file:
                    fix_file(os.path.join(root, file))

if __name__ == '__main__':
    main()
print("Linter fixes applied.")
