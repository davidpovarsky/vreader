// Purpose: JavaScript source constants for EPUB highlight bridge.
// Contains the selection tracking and CSS Highlight API JS injected into WKWebView.
//
// Key decisions:
// - Selection tracking uses debounced selectionchange listener (300ms).
// - XPath serialization covers text nodes and element nodes.
// - CSS Highlight API is the primary path; TreeWalker <mark> fallback for iOS 17.0-17.1.
// - Named color map provides consistent highlight colors across themes.
//
// @coordinates-with: EPUBHighlightBridge.swift, EPUBWebViewBridge.swift

import Foundation

/// JavaScript source constants for the EPUB highlight bridge.
/// Separated from EPUBHighlightBridge to keep file sizes manageable.
extension EPUBHighlightBridge {

    /// JavaScript for tracking text selection changes in the EPUB WKWebView.
    /// Debounced to 300ms. Posts message to Swift with selection details.
    static let selectionTrackingJS = """
    (function() {
        var debounceTimer = null;

        function getXPath(node) {
            if (!node || node.nodeType === 9) return '';
            if (node.nodeType === 3) {
                var parent = node.parentNode;
                if (!parent) return '';
                var textIndex = 0;
                for (var i = 0; i < parent.childNodes.length; i++) {
                    if (parent.childNodes[i] === node) break;
                    if (parent.childNodes[i].nodeType === 3) textIndex++;
                }
                return getXPath(parent) + '/text()[' + (textIndex + 1) + ']';
            }
            if (node.nodeType === 1) {
                var parent = node.parentNode;
                if (!parent) return '/' + node.tagName.toLowerCase();
                var sameTagSiblings = [];
                for (var i = 0; i < parent.childNodes.length; i++) {
                    var sibling = parent.childNodes[i];
                    if (sibling.nodeType === 1 && sibling.tagName === node.tagName) {
                        sameTagSiblings.push(sibling);
                    }
                }
                var index = sameTagSiblings.indexOf(node) + 1;
                var tagName = node.tagName.toLowerCase();
                if (sameTagSiblings.length > 1) {
                    return getXPath(parent) + '/' + tagName + '[' + index + ']';
                }
                return getXPath(parent) + '/' + tagName;
            }
            return '';
        }

        document.addEventListener('selectionchange', function() {
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(function() {
                var sel = window.getSelection();
                if (!sel || sel.isCollapsed || !sel.rangeCount) return;
                var range = sel.getRangeAt(0);
                var text = sel.toString();
                if (!text || !text.trim()) return;

                var rect = range.getBoundingClientRect();
                var msg = {
                    selectedText: text,
                    startPath: getXPath(range.startContainer),
                    startOffset: range.startOffset,
                    endPath: getXPath(range.endContainer),
                    endOffset: range.endOffset,
                    rectX: rect.x,
                    rectY: rect.y,
                    rectWidth: rect.width,
                    rectHeight: rect.height
                };
                window.webkit.messageHandlers.selectionChanged.postMessage(msg);
            }, 300);
        });
    })();
    """

    /// JavaScript implementing the CSS Highlight API bridge functions.
    /// Provides createHighlight, removeHighlight, clearAllHighlights.
    /// Uses CSS Highlight API where available, <mark> fallback otherwise.
    static let highlightAPIJS = """
    (function() {
        var colorMap = {
            'yellow': 'rgba(255, 235, 59, 0.35)',
            'blue': 'rgba(66, 133, 244, 0.30)',
            'green': 'rgba(52, 168, 83, 0.30)',
            'pink': 'rgba(233, 30, 99, 0.25)',
            'orange': 'rgba(255, 152, 0, 0.30)',
            'purple': 'rgba(156, 39, 176, 0.25)'
        };

        var fallbackElements = {};

        function resolveNodeFromXPath(xpath) {
            try {
                var result = document.evaluate(
                    xpath, document, null,
                    XPathResult.FIRST_ORDERED_NODE_TYPE, null
                );
                return result.singleNodeValue;
            } catch (e) {
                return null;
            }
        }

        function buildRange(startPath, startOffset, endPath, endOffset) {
            var startNode = resolveNodeFromXPath(startPath);
            var endNode = resolveNodeFromXPath(endPath);
            if (!startNode || !endNode) return null;
            try {
                var range = document.createRange();
                range.setStart(startNode, Math.min(startOffset, startNode.length || 0));
                range.setEnd(endNode, Math.min(endOffset, endNode.length || 0));
                return range;
            } catch (e) {
                return null;
            }
        }

        function cssColor(color) {
            return colorMap[color] || color;
        }

        var useCSSHighlights = typeof CSS !== 'undefined' && CSS.highlights;

        window.__vreader_createHighlight = function(id, startPath, startOffset, endPath, endOffset, color) {
            var range = buildRange(startPath, startOffset, endPath, endOffset);
            if (!range) return;
            if (useCSSHighlights) {
                try {
                    var highlight = new Highlight(range);
                    CSS.highlights.set('vreader-' + id, highlight);
                    var styleId = 'vreader-hl-style-' + id;
                    if (!document.getElementById(styleId)) {
                        var style = document.createElement('style');
                        style.id = styleId;
                        style.textContent = '::highlight(vreader-' + id + ') { background-color: ' + cssColor(color) + '; }';
                        document.head.appendChild(style);
                    }
                } catch (e) {
                    fallbackCreateHighlight(id, range, color);
                }
            } else {
                fallbackCreateHighlight(id, range, color);
            }
        };

        function fallbackCreateHighlight(id, range, color) {
            try {
                var mark = document.createElement('mark');
                mark.setAttribute('data-vreader-highlight', id);
                mark.style.backgroundColor = cssColor(color);
                mark.style.padding = '0';
                mark.style.margin = '0';
                range.surroundContents(mark);
                fallbackElements[id] = mark;
            } catch (e) {
                // surroundContents fails if range crosses element boundaries
            }
        }

        window.__vreader_removeHighlight = function(id) {
            if (useCSSHighlights) {
                CSS.highlights.delete('vreader-' + id);
                var styleEl = document.getElementById('vreader-hl-style-' + id);
                if (styleEl) styleEl.remove();
            }
            var mark = fallbackElements[id];
            if (mark && mark.parentNode) {
                var parent = mark.parentNode;
                while (mark.firstChild) {
                    parent.insertBefore(mark.firstChild, mark);
                }
                parent.removeChild(mark);
                delete fallbackElements[id];
            }
        };

        window.__vreader_clearAllHighlights = function() {
            if (useCSSHighlights) {
                CSS.highlights.clear();
                var styles = document.querySelectorAll('style[id^="vreader-hl-style-"]');
                styles.forEach(function(s) { s.remove(); });
            }
            var marks = document.querySelectorAll('mark[data-vreader-highlight]');
            marks.forEach(function(mark) {
                var parent = mark.parentNode;
                while (mark.firstChild) {
                    parent.insertBefore(mark.firstChild, mark);
                }
                parent.removeChild(mark);
            });
            fallbackElements = {};
        };
    })();
    """
}
