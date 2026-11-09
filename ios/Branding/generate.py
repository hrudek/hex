#!/usr/bin/env python3
"""Generate Typr's shared vector mark and transparent icon layer from typr-logo.svg.

Local/offline tool; requires rsvg-convert only for PNG rendering. No font dependency.
"""
import argparse
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent

# Optical correction in SVG units (wordmark height 573), applied after the
# visible bounds are centered. The light period widens the bounds, so the heavy
# "typr" sits left; descenders pull the x-height up. Right/down shift balances
# both without fully centering on ink mass, which would crowd the period.
OPTICAL_OFFSET = (39, 12)


def geometry():
    root = ET.parse(HERE / 'typr-logo.svg').getroot()
    paths = root.findall('{http://www.w3.org/2000/svg}path')
    if len(paths) != 1:
        raise ValueError('Expected one outlined wordmark path')
    data = paths[0].attrib['d']
    tokens = re.findall(r'[A-Za-z]|-?\d+(?:\.\d+)?', data)
    commands, points = [], []
    current = (0.0, 0.0)
    start = current
    i = 0
    while i < len(tokens):
        command = tokens[i]
        i += 1
        count = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'Z': 0}.get(command)
        if count is None:
            raise ValueError('Unsupported SVG command: ' + command)
        values = list(map(float, tokens[i:i + count]))
        i += count
        if command in ('M', 'L'):
            current = tuple(values)
            if command == 'M':
                start = current
            points.append(current)
            commands.append(('move' if command == 'M' else 'line', [current]))
        elif command in ('H', 'V'):
            current = (values[0], current[1]) if command == 'H' else (current[0], values[0])
            points.append(current)
            commands.append(('line', [current]))
        elif command == 'C':
            curve = [tuple(values[n:n + 2]) for n in (0, 2, 4)]
            points.extend(curve)
            commands.append(('curve', curve))
            current = curve[-1]
        else:
            commands.append(('close', []))
            current = start
    bounds = (min(p[0] for p in points), min(p[1] for p in points),
              max(p[0] for p in points), max(p[1] for p in points))
    return root, paths[0], commands, bounds


def swift_source():
    _, _, commands, (x0, y0, x1, y1) = geometry()
    def point(p):
        return f'point({p[0]:g}, {p[1]:g})'
    lines = [
        '// Generated from typr-logo.svg by generate.py; edit the SVG, not this file.',
        'import SwiftUI', '',
        '/// The outlined Typr wordmark, aspect-fitted without the icon background.',
        '/// `opticallyCentered` applies the app icon\'s optical offset; use it only',
        '/// when the mark sits centered in a surface, not when aligned to an edge.',
        'struct TyprWordmark: Shape {',
        '    var opticallyCentered = false',
        '',
        f'    static let opticalOffset = CGSize(width: {OPTICAL_OFFSET[0]:g}, height: {OPTICAL_OFFSET[1]:g})',
        '',
        '    func path(in rect: CGRect) -> Path {',
        f'        let width: CGFloat = {x1 - x0:g}',
        f'        let height: CGFloat = {y1 - y0:g}',
        '        let scale = min(rect.width / width, rect.height / height)',
        '        let offset = opticallyCentered ? Self.opticalOffset : .zero',
        '        let origin = CGPoint(x: rect.midX - width * scale / 2 + offset.width * scale,',
        '                             y: rect.midY - height * scale / 2 + offset.height * scale)',
        '        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {',
        f'            CGPoint(x: origin.x + (x - {x0:g}) * scale,',
        f'                    y: origin.y + (y - {y0:g}) * scale)',
        '        }',
        '        var path = Path()',
    ]
    for kind, pts in commands:
        if kind == 'curve':
            lines.append(f'        path.addCurve(to: {point(pts[2])}, control1: {point(pts[0])}, control2: {point(pts[1])})')
        elif kind == 'close':
            lines.append('        path.closeSubpath()')
        else:
            method = 'move' if kind == 'move' else 'addLine'
            lines.append(f'        path.{method}(to: {point(pts[0])})')
    lines += ['        return path', '    }', '}', '']
    return '\n'.join(lines)


def render_layer(destination):
    root, path, _, (x0, y0, x1, y1) = geometry()
    # Preserve the source's wordmark proportions; center its visible bounds on
    # the 2000-square canvas, then apply the optical offset. The background
    # belongs to Icon Composer, not the PNG.
    for child in list(root):
        if child is not path:
            root.remove(child)
    dx = 1000 - (x0 + x1) / 2 + OPTICAL_OFFSET[0]
    dy = 1000 - (y0 + y1) / 2 + OPTICAL_OFFSET[1]
    path.set('transform', f'translate({dx:g} {dy:g})')
    subprocess.run(['rsvg-convert', '--width', '2048', '--height', '2048',
                    '--output', str(destination)], input=ET.tostring(root), check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check the generated vector without rendering')
    args = parser.parse_args()
    destination = HERE / 'TyprWordmark.swift'
    source = swift_source()
    if args.check:
        if destination.read_text() != source:
            raise SystemExit('Regenerate TyprWordmark.swift from typr-logo.svg')
    else:
        destination.write_text(source)
        render_layer(HERE.parent / 'AppIcon.icon/Assets/Image.png')


if __name__ == '__main__':
    main()
