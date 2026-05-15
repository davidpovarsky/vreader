// Reader screen — paginated reading with chrome, themes, highlight selection

function ReaderScreen({ book, theme, fontFamily, fontSize, lineHeight, margin,
                        onClose, onOpenAI, onOpenTOC, onOpenHighlights,
                        onOpenSettings, onOpenReaderSettings,
                        pageIdx, onPageChange, highlights, onAddHighlight, brightness }) {
  const [chromeVisible, setChromeVisible] = React.useState(true);
  const [selection, setSelection] = React.useState(null); // {text, paraIdx, range}
  const [pageDir, setPageDir] = React.useState(0); // -1 prev, 1 next
  const [animating, setAnimating] = React.useState(false);
  const [bookmarked, setBookmarked] = React.useState(false);

  const pageRef = React.useRef(null);
  const t = theme;

  const totalPages = book.pages;
  const startPage = book.currentPage;
  const displayPage = Math.min(startPage + pageIdx, totalPages);
  const progress = displayPage / totalPages;
  const pageData = PP_PAGES[pageIdx % PP_PAGES.length];

  const turnPage = (dir) => {
    if (animating) return;
    if (pageIdx + dir < 0) return;
    setPageDir(dir);
    setAnimating(true);
    setSelection(null);
    setTimeout(() => {
      onPageChange(pageIdx + dir);
      setTimeout(() => setAnimating(false), 50);
    }, 280);
  };

  const handleTap = (e) => {
    if (selection) { setSelection(null); return; }
    const rect = pageRef.current.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const w = rect.width;
    if (x < w * 0.3) turnPage(-1);
    else if (x > w * 0.7) turnPage(1);
    else setChromeVisible(c => !c);
  };

  const handleLongPress = (paraIdx) => {
    // simulate selection of a sentence
    const para = pageData.paragraphs[paraIdx];
    const firstSentence = para.split(/(?<=[.!?])\s+/)[0];
    setSelection({ text: firstSentence, paraIdx });
    setChromeVisible(false);
  };

  // Background — handles theme + optional photo
  const bgStyle = {
    position: 'absolute', inset: 0,
    background: t.bg,
  };
  const photoBg = t.image && (
    <div style={{
      position: 'absolute', inset: 0,
      backgroundImage: 'linear-gradient(135deg, #3a2818 0%, #1a1410 60%, #2a1818 100%)',
      filter: 'saturate(1.1)',
    }}>
      {/* subtle texture overlay simulating an image */}
      <div style={{
        position: 'absolute', inset: 0, opacity: 0.5,
        background: 'radial-gradient(ellipse at 20% 30%, rgba(216,136,90,0.18) 0%, transparent 50%), radial-gradient(ellipse at 80% 70%, rgba(122,58,31,0.18) 0%, transparent 50%)',
      }}/>
    </div>
  );

  // Apply brightness as dimming overlay
  const brightnessOverlay = brightness < 1 && (
    <div style={{
      position: 'absolute', inset: 0, pointerEvents: 'none', zIndex: 100,
      background: '#000', opacity: (1 - brightness) * 0.55,
    }}/>
  );

  return (
    <div style={{
      position: 'relative', width: '100%', height: '100%',
      overflow: 'hidden', background: t.bg, color: t.ink,
      fontFamily: '"Inter", -apple-system, system-ui',
    }}>
      {photoBg}

      {/* Page content */}
      <div ref={pageRef} onClick={handleTap} style={{
        position: 'absolute', inset: 0,
        cursor: 'pointer',
      }}>
        {/* Status bar gradient when chrome visible */}
        {chromeVisible && !t.image && (
          <div style={{
            position: 'absolute', top: 0, left: 0, right: 0, height: 90,
            background: `linear-gradient(to bottom, ${t.chrome}, ${t.chrome.replace(/[\d.]+\)/, '0)')})`,
            pointerEvents: 'none', zIndex: 5,
          }}/>
        )}

        {/* Chapter header */}
        <div style={{
          position: 'absolute', top: 54, left: 0, right: 0,
          padding: `0 ${margin}px`, textAlign: 'center',
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 11, color: t.sub, letterSpacing: 1.5,
          textTransform: 'uppercase', fontWeight: 500, zIndex: 6,
          pointerEvents: 'none',
        }}>
          {chromeVisible ? '' : pageData.chapter}
        </div>

        {/* Page text */}
        <PageContent
          page={pageData} theme={t} fontFamily={fontFamily}
          fontSize={fontSize} lineHeight={lineHeight} margin={margin}
          pageDir={pageDir} animating={animating} pageIdx={pageIdx}
          highlights={highlights} selection={selection}
          onLongPress={handleLongPress}
        />

        {/* Footer — page number + progress */}
        <div style={{
          position: 'absolute', bottom: 26, left: 0, right: 0,
          padding: `0 ${margin}px`,
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          fontFamily: '"Inter", system-ui', fontSize: 11,
          color: t.sub, zIndex: 6, pointerEvents: 'none',
        }}>
          <span>{Math.round(progress * 100)}%</span>
          <span style={{ letterSpacing: 0.5 }}>{displayPage} / {totalPages}</span>
        </div>
      </div>

      {/* Top chrome */}
      {chromeVisible && (
        <ReaderTopChrome
          book={book} theme={t} bookmarked={bookmarked}
          onClose={onClose} onToggleBookmark={() => setBookmarked(b => !b)}
          onMore={onOpenSettings}/>
      )}

      {/* Bottom chrome */}
      {chromeVisible && (
        <ReaderBottomChrome
          theme={t} progress={progress} displayPage={displayPage} totalPages={totalPages}
          onOpenAI={onOpenAI} onOpenTOC={onOpenTOC}
          onOpenHighlights={onOpenHighlights} onOpenReaderSettings={onOpenReaderSettings}
          onScrub={(p) => onPageChange(Math.round(p * (totalPages - startPage)))}/>
      )}

      {/* Selection popover */}
      {selection && (
        <SelectionPopover
          selection={selection} theme={t}
          onHighlight={(color) => {
            onAddHighlight({ text: selection.text, color, paraIdx: selection.paraIdx, pageIdx });
            setSelection(null);
          }}
          onTranslate={() => { setSelection(null); onOpenAI('translate', selection.text); }}
          onAsk={() => { setSelection(null); onOpenAI('chat', selection.text); }}
          onClose={() => setSelection(null)}
        />
      )}

      {brightnessOverlay}
    </div>
  );
}

// ────────────────────────────────────────────────────
// Page content (text)
// ────────────────────────────────────────────────────
function PageContent({ page, theme, fontFamily, fontSize, lineHeight, margin,
                       pageDir, animating, pageIdx, highlights, selection, onLongPress }) {
  const t = theme;
  const ff = fontFamily === 'serif'
    ? '"Source Serif 4", Georgia, "Times New Roman", serif'
    : '"Inter", -apple-system, system-ui, sans-serif';

  // animation transform
  const animTransform = animating
    ? `translateX(${pageDir > 0 ? -8 : 8}%) `
    : 'translateX(0) ';
  const animOpacity = animating ? 0 : 1;

  return (
    <div style={{
      position: 'absolute', top: 76, bottom: 56,
      left: margin, right: margin,
      overflow: 'hidden',
      transform: animTransform,
      opacity: animOpacity,
      transition: 'transform 0.28s cubic-bezier(0.32, 0.72, 0, 1), opacity 0.22s ease-out',
    }}>
      {/* Chapter heading when paragraphs start a chapter */}
      {(pageIdx === 0 || page.chapter !== PP_PAGES[(pageIdx - 1 + PP_PAGES.length) % PP_PAGES.length].chapter) && (
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 13, color: t.sub, letterSpacing: 2,
          textTransform: 'uppercase', textAlign: 'center',
          marginBottom: 18, marginTop: 8, fontWeight: 500,
        }}>
          {page.chapter}
        </div>
      )}
      {page.paragraphs.map((para, i) => (
        <Paragraph key={`${pageIdx}-${i}`} text={para} idx={i}
          first={i === 0} ff={ff} fontSize={fontSize} lineHeight={lineHeight}
          theme={t} highlights={highlights.filter(h => h.pageIdx === pageIdx && h.paraIdx === i)}
          selection={selection && selection.paraIdx === i ? selection : null}
          onLongPress={onLongPress}
        />
      ))}
    </div>
  );
}

function Paragraph({ text, idx, first, ff, fontSize, lineHeight, theme, highlights, selection, onLongPress }) {
  const timerRef = React.useRef(null);

  const startHold = (e) => {
    if (e && e.stopPropagation) e.stopPropagation();
    timerRef.current = setTimeout(() => { onLongPress(idx); }, 380);
  };
  const cancelHold = () => clearTimeout(timerRef.current);

  // Render text with highlights + selection
  const segments = buildSegments(text, highlights, selection);

  return (
    <p
      onMouseDown={startHold} onMouseUp={cancelHold} onMouseLeave={cancelHold}
      onTouchStart={startHold} onTouchEnd={cancelHold}
      onClick={(e) => { /* let parent handle */ }}
      style={{
        fontFamily: ff,
        fontSize, lineHeight, color: theme.ink,
        margin: 0, marginBottom: lineHeight * fontSize * 0.4,
        textIndent: first ? 0 : `${fontSize * 1.4}px`,
        textAlign: 'justify', hyphens: 'auto',
        WebkitUserSelect: 'none', userSelect: 'none',
      }}>
      {first && (
        <span style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: fontSize * 2.6, lineHeight: 0.85,
          float: 'left', marginRight: 6, marginTop: 4,
          color: theme.accent, fontWeight: 600,
        }}>{text[0]}</span>
      )}
      {first ? <Segments segments={segments} skipFirst /> : <Segments segments={segments} />}
    </p>
  );
}

function Segments({ segments, skipFirst = false }) {
  return segments.map((seg, i) => {
    const text = skipFirst && i === 0 ? seg.text.slice(1) : seg.text;
    if (seg.kind === 'highlight') {
      const colors = {
        yellow: 'rgba(240,210,90,0.45)',
        pink: 'rgba(232,140,160,0.4)',
        green: 'rgba(140,200,140,0.4)',
        blue: 'rgba(140,180,232,0.4)',
      };
      return <span key={i} style={{
        background: colors[seg.color] || colors.yellow,
        padding: '0 1px', borderRadius: 2,
        boxShadow: 'inset 0 -1px 0 rgba(0,0,0,0.04)',
      }}>{text}</span>;
    }
    if (seg.kind === 'selection') {
      return <span key={i} style={{
        background: 'rgba(120,140,232,0.35)',
        boxShadow: '0 0 0 1px rgba(80,100,200,0.5)',
        borderRadius: 2,
      }}>{text}</span>;
    }
    return <span key={i}>{text}</span>;
  });
}

function buildSegments(text, highlights, selection) {
  // marks: array of {start, end, kind, color?}
  const marks = [];
  highlights.forEach(h => {
    const idx = text.indexOf(h.text);
    if (idx >= 0) marks.push({ start: idx, end: idx + h.text.length, kind: 'highlight', color: h.color });
  });
  if (selection) {
    const idx = text.indexOf(selection.text);
    if (idx >= 0) marks.push({ start: idx, end: idx + selection.text.length, kind: 'selection' });
  }
  marks.sort((a, b) => a.start - b.start);
  const segs = [];
  let pos = 0;
  marks.forEach(m => {
    if (m.start > pos) segs.push({ kind: 'plain', text: text.slice(pos, m.start) });
    segs.push({ kind: m.kind, color: m.color, text: text.slice(m.start, m.end) });
    pos = m.end;
  });
  if (pos < text.length) segs.push({ kind: 'plain', text: text.slice(pos) });
  if (segs.length === 0) segs.push({ kind: 'plain', text });
  return segs;
}

// ────────────────────────────────────────────────────
// Top + bottom chrome
// ────────────────────────────────────────────────────
function ReaderTopChrome({ book, theme, bookmarked, onClose, onToggleBookmark, onMore }) {
  const t = theme;
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0,
      paddingTop: 50, paddingBottom: 12, zIndex: 30,
      background: t.image ? 'rgba(0,0,0,0.55)' : t.chrome,
      borderBottom: `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 14px',
      }}>
        <button onClick={onClose} style={{
          display: 'flex', alignItems: 'center', gap: 4,
          padding: '6px 8px', background: 'none', border: 'none', cursor: 'pointer',
          color: t.accent, fontFamily: 'inherit', fontSize: 15, fontWeight: 500,
        }}>
          <Icons.ChevronL size={20} color={t.accent} stroke={2.2}/>
          <span>Library</span>
        </button>
        <div style={{
          flex: 1, textAlign: 'center', padding: '0 8px',
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 14, fontWeight: 600, color: t.ink, fontStyle: 'italic',
        }}>{book.title}</div>
        <div style={{ display: 'flex', gap: 4 }}>
          <button onClick={onToggleBookmark} style={iconBtnStyle(t)}>
            {bookmarked
              ? <Icons.BookmarkFilled size={18} color={t.accent} stroke={1.8}/>
              : <Icons.Bookmark size={18} color={t.ink} stroke={1.7}/>}
          </button>
          <button onClick={onMore} style={iconBtnStyle(t)}>
            <Icons.More size={20} color={t.ink} stroke={1.7}/>
          </button>
        </div>
      </div>
    </div>
  );
}

function iconBtnStyle(t) {
  return {
    width: 36, height: 36, borderRadius: 18,
    background: 'none', border: 'none', cursor: 'pointer',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
  };
}

function ReaderBottomChrome({ theme, progress, displayPage, totalPages,
                              onOpenAI, onOpenTOC, onOpenHighlights, onOpenReaderSettings,
                              onScrub }) {
  const t = theme;
  const trackRef = React.useRef(null);

  const handleScrub = (e) => {
    const rect = trackRef.current.getBoundingClientRect();
    const p = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    onScrub(p);
  };

  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0,
      paddingBottom: 28, paddingTop: 14, zIndex: 30,
      background: t.image ? 'rgba(0,0,0,0.55)' : t.chrome,
      borderTop: `0.5px solid ${t.rule}`,
    }}>
      {/* Scrubber */}
      <div style={{ padding: '0 22px', marginBottom: 14 }}>
        <div ref={trackRef} onClick={handleScrub} style={{
          height: 24, display: 'flex', alignItems: 'center', cursor: 'pointer',
        }}>
          <div style={{
            flex: 1, height: 3, borderRadius: 2,
            background: t.rule, position: 'relative',
          }}>
            <div style={{
              position: 'absolute', left: 0, top: 0, bottom: 0,
              width: `${progress * 100}%`, background: t.accent, borderRadius: 2,
            }}/>
            <div style={{
              position: 'absolute', left: `${progress * 100}%`, top: '50%',
              width: 14, height: 14, borderRadius: 7, background: t.accent,
              transform: 'translate(-50%, -50%)',
              boxShadow: '0 1px 3px rgba(0,0,0,0.3)',
            }}/>
          </div>
        </div>
        <div style={{
          display: 'flex', justifyContent: 'space-between',
          fontFamily: 'inherit', fontSize: 11, color: t.sub, marginTop: 4,
        }}>
          <span>Page {displayPage}</span>
          <span>{totalPages - displayPage} pages left in book</span>
        </div>
      </div>
      {/* Toolbar */}
      <div style={{
        display: 'flex', justifyContent: 'space-around',
        padding: '0 12px',
      }}>
        {[
          { icon: Icons.TOC,    label: 'Contents',  on: onOpenTOC },
          { icon: Icons.Highlighter, label: 'Notes', on: onOpenHighlights },
          { icon: Icons.Aa,     label: 'Display',   on: onOpenReaderSettings },
          { icon: Icons.Sparkle,label: 'AI',        on: onOpenAI, accent: true },
        ].map((b, i) => (
          <button key={i} onClick={() => b.on()} style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
            padding: '4px 12px', background: 'none', border: 'none', cursor: 'pointer',
          }}>
            <b.icon size={22} color={b.accent ? t.accent : t.ink} stroke={1.8}/>
            <span style={{
              fontSize: 10, color: b.accent ? t.accent : t.sub, fontWeight: 500,
            }}>{b.label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Selection popover (highlight / translate / ask AI)
// ────────────────────────────────────────────────────
function SelectionPopover({ selection, theme, onHighlight, onTranslate, onAsk, onClose }) {
  const t = theme;
  const colors = ['yellow', 'pink', 'green', 'blue'];
  const colorMap = {
    yellow: '#f0d25a', pink: '#e88ca0', green: '#8cc88c', blue: '#8cb4e8',
  };
  return (
    <div style={{
      position: 'absolute', left: 18, right: 18, bottom: 100, zIndex: 60,
      borderRadius: 18, padding: 14,
      background: t.isDark ? '#2a2724' : '#fcf8f0',
      boxShadow: '0 10px 40px rgba(0,0,0,0.25), 0 0 0 0.5px ' + t.rule,
    }}>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 13, fontStyle: 'italic', color: t.sub,
        marginBottom: 12, lineHeight: 1.4,
        overflow: 'hidden', display: '-webkit-box',
        WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
      }}>"{selection.text}"</div>
      <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 10 }}>
        {colors.map(c => (
          <button key={c} onClick={() => onHighlight(c)} style={{
            width: 30, height: 30, borderRadius: 15, padding: 0,
            background: colorMap[c], border: '2px solid rgba(255,255,255,0.4)',
            cursor: 'pointer', boxShadow: '0 1px 3px rgba(0,0,0,0.15)',
          }}/>
        ))}
        <div style={{ flex: 1 }}/>
        <button onClick={onClose} style={iconBtnStyle(t)}>
          <Icons.Close size={16} color={t.sub} stroke={2}/>
        </button>
      </div>
      <div style={{
        display: 'flex', gap: 8, paddingTop: 10,
        borderTop: `0.5px solid ${t.rule}`,
      }}>
        {[
          { icon: Icons.Note,      label: 'Note',      on: () => onHighlight('yellow') },
          { icon: Icons.Translate, label: 'Translate', on: onTranslate },
          { icon: Icons.Sparkle,   label: 'Ask AI',    on: onAsk, primary: true },
          { icon: Icons.Volume,    label: 'Read',      on: () => {} },
        ].map((b, i) => (
          <button key={i} onClick={b.on} style={{
            flex: 1, display: 'flex', flexDirection: 'column',
            alignItems: 'center', gap: 4, padding: '8px 4px',
            borderRadius: 10, background: b.primary ? t.accent : 'transparent',
            border: 'none', cursor: 'pointer',
            color: b.primary ? '#fff' : t.ink,
          }}>
            <b.icon size={18} color={b.primary ? '#fff' : t.ink} stroke={1.7}/>
            <span style={{ fontSize: 10.5, fontWeight: 500 }}>{b.label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { ReaderScreen });
