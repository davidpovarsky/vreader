// Library screen — grid + list, search, sort

function LibraryScreen({ onOpenBook, onOpenSettings }) {
  const [view, setView] = React.useState('grid'); // grid | list
  const [query, setQuery] = React.useState('');
  const [filter, setFilter] = React.useState('All');
  const [showSearch, setShowSearch] = React.useState(false);

  const filtered = BOOKS.filter(b => {
    if (filter !== 'All' && !b.tags.includes(filter)) return false;
    if (query && !b.title.toLowerCase().includes(query.toLowerCase())
              && !b.author.toLowerCase().includes(query.toLowerCase())) return false;
    return true;
  });
  const reading = filtered.filter(b => b.progress > 0 && b.progress < 1);
  const recent = [...reading].sort((a,b) => {
    const order = { 'Just now': 0, '2h ago': 1, '12h ago': 2, 'Yesterday': 3, '2d ago': 4, '3d ago': 5, '4d ago': 6, '5d ago': 7, '1w ago': 8, '2w ago': 9, 'Never': 99 };
    return (order[a.lastRead] ?? 50) - (order[b.lastRead] ?? 50);
  });

  return (
    <div style={{
      width: '100%', height: '100%', background: '#f7f4ee',
      display: 'flex', flexDirection: 'column',
      fontFamily: '"Inter", -apple-system, system-ui',
      color: '#1d1a14',
    }}>
      {/* Status bar room */}
      <div style={{ height: 54 }} />

      {/* Nav bar */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '6px 18px 0',
      }}>
        <button onClick={onOpenSettings} style={pillBtn}>
          <Icons.Settings size={19} color="#3a2913" stroke={1.7}/>
        </button>
        <div style={{ display: 'flex', gap: 8 }}>
          <button onClick={() => setShowSearch(s => !s)} style={pillBtn}>
            <Icons.Search size={19} color="#3a2913" stroke={1.7}/>
          </button>
          <button style={pillBtn} onClick={() => setView(v => v === 'grid' ? 'list' : 'grid')}>
            {view === 'grid'
              ? <Icons.List size={19} color="#3a2913" stroke={1.7}/>
              : <Icons.Grid size={19} color="#3a2913" stroke={1.7}/>}
          </button>
          <button style={pillBtn}>
            <Icons.Plus size={19} color="#3a2913" stroke={1.7}/>
          </button>
        </div>
      </div>

      {/* Title */}
      <div style={{
        padding: '12px 22px 8px',
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 36, fontWeight: 600, letterSpacing: -0.8,
        color: '#1d1a14',
      }}>Library</div>
      <div style={{
        padding: '0 22px 16px', fontSize: 13, color: '#7a6a4a',
        letterSpacing: 0.1,
      }}>{BOOKS.length} books · {reading.length} reading</div>

      {/* Search bar */}
      {showSearch && (
        <div style={{ padding: '0 18px 12px' }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8,
            padding: '10px 14px', borderRadius: 12,
            background: 'rgba(60,40,20,0.06)',
          }}>
            <Icons.Search size={16} color="#7a6a4a" stroke={1.7}/>
            <input
              autoFocus
              placeholder="Search title, author, content…"
              value={query}
              onChange={e => setQuery(e.target.value)}
              style={{
                flex: 1, border: 'none', outline: 'none', background: 'transparent',
                fontFamily: 'inherit', fontSize: 15, color: '#1d1a14',
              }}/>
            {query && (
              <button onClick={() => setQuery('')} style={{ background: 'none', border: 'none', padding: 2, cursor: 'pointer' }}>
                <Icons.Close size={15} color="#7a6a4a" stroke={1.8}/>
              </button>
            )}
          </div>
        </div>
      )}

      {/* Filter chips */}
      <div style={{
        display: 'flex', gap: 6, padding: '0 18px 14px', overflowX: 'auto',
        scrollbarWidth: 'none',
      }} className="hide-scroll">
        {['All', 'Fiction', 'Non-fiction', 'Technical', 'Classics', 'CJK'].map(f => (
          <button key={f} onClick={() => setFilter(f)} style={{
            padding: '6px 12px', borderRadius: 100, border: 'none',
            fontFamily: 'inherit', fontSize: 13, fontWeight: 500,
            background: filter === f ? '#1d1a14' : 'rgba(60,40,20,0.06)',
            color: filter === f ? '#f7f4ee' : '#3a2913',
            cursor: 'pointer', whiteSpace: 'nowrap',
          }}>{f}</button>
        ))}
      </div>

      {/* Continue reading rail (only on All / no query) */}
      <div style={{ flex: 1, overflow: 'auto', paddingBottom: 60 }} className="hide-scroll">
        {filter === 'All' && !query && (
          <div style={{ marginBottom: 24 }}>
            <div style={{
              display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
              padding: '0 22px 10px',
            }}>
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 18, fontWeight: 600, color: '#1d1a14',
                whiteSpace: 'nowrap',
              }}>Continue reading</div>
              <div style={{ fontSize: 13, color: '#8c2f2f', fontWeight: 500, whiteSpace: 'nowrap' }}>See all</div>
            </div>
            <div style={{
              display: 'flex', gap: 14, padding: '0 22px',
              overflowX: 'auto', scrollbarWidth: 'none',
            }} className="hide-scroll">
              {recent.slice(0, 5).map(b => (
                <ContinueCard key={b.id} book={b} onOpen={onOpenBook}/>
              ))}
            </div>
          </div>
        )}

        {/* Main list */}
        {view === 'grid' ? (
          <GridView books={filtered} onOpen={onOpenBook}/>
        ) : (
          <ListView books={filtered} onOpen={onOpenBook}/>
        )}
      </div>
    </div>
  );
}

const pillBtn = {
  width: 36, height: 36, borderRadius: 18,
  background: 'rgba(60,40,20,0.06)', border: 'none', cursor: 'pointer',
  display: 'flex', alignItems: 'center', justifyContent: 'center',
};

function ContinueCard({ book, onOpen }) {
  return (
    <button onClick={() => onOpen(book)} style={{
      width: 124, padding: 0, border: 'none', background: 'transparent',
      display: 'flex', flexDirection: 'column', gap: 10, cursor: 'pointer',
      textAlign: 'left', flexShrink: 0,
    }}>
      <div style={{ position: 'relative' }}>
        <BookCover book={book} width={124} height={186} radius={5}/>
        {/* progress strip */}
        <div style={{
          position: 'absolute', left: 6, right: 6, bottom: 5,
          height: 2.5, borderRadius: 2, background: 'rgba(255,255,255,0.22)',
          overflow: 'hidden',
        }}>
          <div style={{
            height: '100%', width: `${book.progress * 100}%`,
            background: 'rgba(255,255,255,0.92)', borderRadius: 2,
          }}/>
        </div>
      </div>
      <div style={{ padding: '0 2px' }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 13.5, fontWeight: 600, lineHeight: 1.2,
          color: '#1d1a14',
          overflow: 'hidden', display: '-webkit-box',
          WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
        }}>{book.title}</div>
        <div style={{
          fontSize: 11, color: '#7a6a4a', marginTop: 4,
          display: 'flex', alignItems: 'center', gap: 5,
        }}>
          <span style={{ fontWeight: 500 }}>{Math.round(book.progress * 100)}%</span>
          <span style={{ opacity: 0.4 }}>·</span>
          <span style={{
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', flex: 1,
          }}>{book.lastRead}</span>
        </div>
      </div>
    </button>
  );
}

function GridView({ books, onOpen }) {
  return (
    <div style={{ padding: '0 22px' }}>
      <div style={{
        display: 'flex', alignItems: 'baseline',
        justifyContent: 'space-between', marginBottom: 14,
      }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 18, fontWeight: 600, color: '#1d1a14',
          whiteSpace: 'nowrap',
        }}>All books</div>
        <button style={{
          display: 'flex', alignItems: 'center', gap: 4,
          padding: 0, background: 'none', border: 'none', cursor: 'pointer',
          fontSize: 13, color: '#7a6a4a',
        }}>
          <span>Recent</span>
          <Icons.ChevronD size={14} color="#7a6a4a" stroke={2}/>
        </button>
      </div>
      <div style={{
        display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)',
        gap: '22px 14px',
      }}>
        {books.map(b => (
          <button key={b.id} onClick={() => onOpen(b)} style={{
            background: 'none', border: 'none', padding: 0, cursor: 'pointer',
            textAlign: 'left', display: 'flex', flexDirection: 'column', gap: 8,
          }}>
            <div style={{ position: 'relative', width: '100%' }}>
              <BookCover book={b} width={104} height={156} radius={4}/>
              {/* progress ring or strip */}
              {b.progress > 0 && b.progress < 1 && (
                <div style={{
                  position: 'absolute', left: 6, right: 6, bottom: 4,
                  height: 2.5, borderRadius: 2, background: 'rgba(255,255,255,0.2)',
                  overflow: 'hidden',
                }}>
                  <div style={{
                    height: '100%', width: `${b.progress * 100}%`,
                    background: 'rgba(255,255,255,0.9)',
                  }}/>
                </div>
              )}
              {b.progress === 1 && (
                <div style={{
                  position: 'absolute', top: 6, right: 6,
                  width: 18, height: 18, borderRadius: 9,
                  background: 'rgba(255,255,255,0.95)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <Icons.Check size={11} color="#3a6a5a" stroke={2.5}/>
                </div>
              )}
            </div>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 12.5, fontWeight: 600, lineHeight: 1.2,
              color: '#1d1a14',
              overflow: 'hidden', display: '-webkit-box',
              WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
            }}>{b.title}</div>
            <div style={{
              fontSize: 10.5, color: '#7a6a4a', marginTop: -4,
            }}>{b.author}</div>
          </button>
        ))}
      </div>
    </div>
  );
}

function ListView({ books, onOpen }) {
  return (
    <div style={{ padding: '0 18px' }}>
      <div style={{
        background: '#fff', borderRadius: 20, overflow: 'hidden',
        boxShadow: '0 1px 0 rgba(0,0,0,0.04)',
      }}>
        {books.map((b, i) => (
          <button key={b.id} onClick={() => onOpen(b)} style={{
            display: 'flex', alignItems: 'center', gap: 12,
            padding: '12px 14px', background: 'none', border: 'none', cursor: 'pointer',
            width: '100%', textAlign: 'left',
            borderTop: i === 0 ? 'none' : '0.5px solid rgba(60,40,20,0.08)',
          }}>
            <BookCover book={b} width={44} height={62} radius={3}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 15, fontWeight: 600, color: '#1d1a14',
                overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
              }}>{b.title}</div>
              <div style={{ fontSize: 12, color: '#7a6a4a', marginTop: 2 }}>
                {b.author}
              </div>
              <div style={{
                display: 'flex', alignItems: 'center', gap: 8,
                marginTop: 5, fontSize: 11, color: '#7a6a4a',
              }}>
                <span style={{
                  padding: '1px 6px', borderRadius: 4,
                  background: 'rgba(60,40,20,0.08)', fontSize: 9.5, fontWeight: 600,
                  letterSpacing: 0.5,
                }}>{b.format}</span>
                {b.progress > 0 && b.progress < 1 && (
                  <span>{Math.round(b.progress * 100)}% · {b.lastRead}</span>
                )}
                {b.progress === 1 && <span style={{ color: '#3a6a5a' }}>Finished</span>}
                {b.progress === 0 && <span>{b.pages} pages</span>}
              </div>
            </div>
            {b.progress > 0 && b.progress < 1 && (
              <div style={{
                width: 30, height: 30, position: 'relative', flexShrink: 0,
              }}>
                <svg width="30" height="30" viewBox="0 0 30 30">
                  <circle cx="15" cy="15" r="12" fill="none" stroke="rgba(60,40,20,0.12)" strokeWidth="2"/>
                  <circle cx="15" cy="15" r="12" fill="none" stroke="#8c2f2f" strokeWidth="2"
                    strokeDasharray={`${b.progress * 75.4} 75.4`}
                    strokeDashoffset={0} transform="rotate(-90 15 15)" strokeLinecap="round"/>
                </svg>
              </div>
            )}
          </button>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { LibraryScreen });
