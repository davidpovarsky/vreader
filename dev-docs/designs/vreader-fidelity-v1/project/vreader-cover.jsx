// Book cover — generative typographic covers per book style

function BookCover({ book, width = 110, height = 165, radius = 4 }) {
  const c = book.cover;
  const style = c.style;
  return (
    <div style={{
      width, height, borderRadius: radius, position: 'relative', overflow: 'hidden',
      background: c.bg, color: c.ink,
      boxShadow: '0 1px 2px rgba(0,0,0,0.18), 0 8px 24px rgba(0,0,0,0.18), inset 0 0 0 1px rgba(0,0,0,0.06)',
      flexShrink: 0,
    }}>
      {/* spine shadow */}
      <div style={{
        position: 'absolute', left: 0, top: 0, bottom: 0, width: 6,
        background: 'linear-gradient(to right, rgba(0,0,0,0.25), rgba(0,0,0,0) 60%)',
        pointerEvents: 'none',
      }}/>
      {/* page edge */}
      <div style={{
        position: 'absolute', right: 0, top: 0, bottom: 0, width: 2,
        background: 'linear-gradient(to left, rgba(255,255,255,0.18), rgba(0,0,0,0.12))',
        pointerEvents: 'none',
      }}/>

      <CoverArt book={book} width={width} height={height} />
    </div>
  );
}

function CoverArt({ book, width, height }) {
  const c = book.cover;
  const w = typeof width === 'number' && !isNaN(width) ? width : 110;
  const titleSize = Math.max(11, w * 0.13) || 13;
  const authorSize = Math.max(8, w * 0.075) || 9;
  const padding = (w * 0.11) || 12;

  if (c.style === 'classic') {
    return (
      <div style={{
        position: 'absolute', inset: padding, display: 'flex',
        flexDirection: 'column', justifyContent: 'space-between',
      }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontWeight: 600, fontSize: titleSize, lineHeight: 1.1,
          fontStyle: 'italic', color: c.ink, letterSpacing: 0.2,
        }}>{book.title}</div>
        <div style={{
          width: '50%', height: 1, background: c.accent, opacity: 0.7,
          margin: '4px 0',
        }}/>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: authorSize, color: c.ink, opacity: 0.85,
          letterSpacing: 0.4, textTransform: 'uppercase',
        }}>{book.author}</div>
      </div>
    );
  }
  if (c.style === 'modern') {
    return (
      <div style={{ position: 'absolute', inset: 0 }}>
        <div style={{
          position: 'absolute', top: padding * 1.5, left: padding,
          right: padding, fontFamily: '"Inter", system-ui',
          fontWeight: 800, fontSize: titleSize * 1.1, lineHeight: 1,
          color: c.ink, letterSpacing: -0.5,
        }}>{book.title}</div>
        <div style={{
          position: 'absolute', bottom: padding, left: padding, right: padding,
        }}>
          <div style={{
            width: 24, height: 2, background: c.accent, marginBottom: 6,
          }}/>
          <div style={{
            fontFamily: '"Inter", system-ui', fontSize: authorSize,
            fontWeight: 500, color: c.ink, opacity: 0.8,
          }}>{book.author}</div>
        </div>
      </div>
    );
  }
  if (c.style === 'animal') {
    // O'Reilly-style: animal silhouette block + title
    return (
      <div style={{ position: 'absolute', inset: 0,
        display: 'flex', flexDirection: 'column',
      }}>
        <div style={{
          padding: `${padding}px ${padding}px 4px`,
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontWeight: 700, fontSize: titleSize * 0.95, lineHeight: 1.05,
          color: c.ink,
        }}>{book.title}</div>
        <div style={{ flex: 1, position: 'relative', margin: padding * 0.5 }}>
          {/* abstract animal block */}
          <div style={{
            position: 'absolute', inset: 0,
            background: 'rgba(0,0,0,0.08)',
            border: '1px solid rgba(0,0,0,0.15)',
          }}>
            <svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid meet" style={{ width: '100%', height: '100%' }}>
              <path d="M30 70 Q25 55 35 45 Q40 35 55 35 Q70 35 75 50 Q78 60 72 70 Q68 78 55 78 Q42 78 30 70 Z M65 45 Q70 38 75 42 M28 65 L18 72 M28 72 L18 78" fill="rgba(0,0,0,0.85)" stroke="none"/>
            </svg>
          </div>
        </div>
        <div style={{
          padding: `4px ${padding}px ${padding}px`,
          fontFamily: '"Inter", system-ui', fontSize: authorSize,
          color: c.ink, opacity: 0.85, fontWeight: 500,
        }}>{book.author}</div>
      </div>
    );
  }
  if (c.style === 'editorial') {
    return (
      <div style={{ position: 'absolute', inset: 0 }}>
        <div style={{
          position: 'absolute', top: padding, left: padding, right: padding,
          fontFamily: '"Inter", system-ui', fontSize: authorSize * 0.85,
          fontWeight: 700, color: c.accent, letterSpacing: 1.5,
          textTransform: 'uppercase',
        }}>{book.author.split(' ').slice(-1)[0]}</div>
        <div style={{
          position: 'absolute', top: '40%', left: padding, right: padding,
          transform: 'translateY(-50%)',
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontWeight: 700, fontSize: titleSize * 1.2, lineHeight: 0.95,
          color: c.ink, letterSpacing: -0.5,
        }}>{book.title}</div>
        <div style={{
          position: 'absolute', bottom: padding, left: padding, right: padding,
          display: 'flex', alignItems: 'center', gap: 6,
        }}>
          <div style={{ width: 16, height: 1, background: c.ink, opacity: 0.5 }}/>
          <div style={{
            fontFamily: '"Inter", system-ui', fontSize: authorSize * 0.85,
            color: c.ink, opacity: 0.7, letterSpacing: 0.6,
          }}>{book.year}</div>
        </div>
      </div>
    );
  }
  if (c.style === 'minimal') {
    return (
      <div style={{
        position: 'absolute', inset: 0,
        display: 'flex', flexDirection: 'column', justifyContent: 'center',
        alignItems: 'center', padding: padding, textAlign: 'center',
      }}>
        <div style={{
          width: 28, height: 28, borderRadius: 14,
          border: `1.5px solid ${c.accent}`, marginBottom: 10,
          position: 'relative',
        }}>
          <div style={{
            position: 'absolute', inset: 6, borderRadius: 8,
            background: c.accent,
          }}/>
        </div>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontWeight: 600, fontSize: titleSize, lineHeight: 1.1,
          color: c.ink, marginBottom: 6,
        }}>{book.title}</div>
        <div style={{
          fontFamily: '"Inter", system-ui', fontSize: authorSize,
          color: c.ink, opacity: 0.7, letterSpacing: 0.3,
        }}>{book.author}</div>
      </div>
    );
  }
  return null;
}

Object.assign(window, { BookCover });
