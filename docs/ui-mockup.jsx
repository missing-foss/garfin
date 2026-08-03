import React, { useState, useMemo } from "react";

const APP_NAME = "Garfin";

/* ------------------------------------------------------------------ data */

const LIBRARIES = [
  { id: "mov", name: "Movies", total: 642 },
  { id: "tv", name: "TV Shows", total: 318 },
  { id: "doc", name: "Documentaries", total: 94 },
  { id: "mus", name: "Music", total: 1840 },
  { id: "home", name: "Home Videos", total: 150 },
];

const KIDS = [
  {
    id: "emma", name: "Emma", age: 7, mode: "allow", tags: ["kids-emma"], cap: "PG",
    libs: { mov: 41, tv: 22, doc: 6, mus: 1840, home: 150 },
    enabled: ["mov", "tv", "doc", "mus", "home"], hue: 152,
  },
  {
    id: "noah", name: "Noah", age: 11, mode: "allow", tags: ["kids-noah"], cap: "PG-13",
    libs: { mov: 118, tv: 61, doc: 24, mus: 1840, home: 150 },
    enabled: ["mov", "tv", "doc", "mus", "home"], hue: 32,
  },
  {
    id: "lea", name: "Léa", age: 14, mode: "block", tags: ["horror", "graphic"], cap: "PG-13",
    libs: { mov: 501, tv: 244, doc: 91, mus: 1840, home: 150 },
    enabled: ["mov", "tv", "doc", "mus", "home"], hue: 265,
  },
  { id: "marc", name: "Marc", admin: true, hue: 210 },
  { id: "guest", name: "Guest", unmanaged: true, hue: 340 },
];

const MANAGED = KIDS.filter((k) => k.mode);

const ITEMS = [
  { id: 1, t: "Paddington", y: 2014, g: "Family", r: "PG", ty: "Movie", grants: ["emma", "noah"] },
  { id: 2, t: "My Neighbour Totoro", y: 1988, g: "Animation", r: "G", ty: "Movie", grants: ["emma"], col: "c-ghibli" },
  { id: 3, t: "The Iron Giant", y: 1999, g: "Animation", r: "PG", ty: "Movie", grants: [] },
  { id: 4, t: "Spirited Away", y: 2001, g: "Animation", r: "PG", ty: "Movie", grants: ["noah"], col: "c-ghibli" },
  { id: 5, t: "Kiki's Delivery Service", y: 1989, g: "Animation", r: "G", ty: "Movie", grants: [], col: "c-ghibli" },
  { id: 6, t: "Jurassic Park", y: 1993, g: "Adventure", r: "PG-13", ty: "Movie", grants: ["noah"], col: "c-jp" },
  { id: 7, t: "Bluey", y: 2018, g: "Family", r: "TV-Y", ty: "Series", grants: ["emma"] },
  { id: 8, t: "Wallace & Gromit", y: 1993, g: "Comedy", r: "G", ty: "Series", grants: [] },
  { id: 9, t: "Avatar: The Last Airbender", y: 2005, g: "Animation", r: "TV-Y7", ty: "Series", grants: ["noah"] },
  { id: 10, t: "Planet Earth", y: 2006, g: "Documentary", r: "G", ty: "Series", grants: ["emma", "noah"] },
  { id: 11, t: "Cosmos", y: 1980, g: "Documentary", r: "G", ty: "Series", grants: [] },
  { id: 12, t: "E.T.", y: 1982, g: "Adventure", r: "PG", ty: "Movie", grants: [] },
  { id: 13, t: "The Goonies", y: 1985, g: "Adventure", r: "PG", ty: "Movie", grants: [] },
  { id: 14, t: "Ratatouille", y: 2007, g: "Animation", r: "G", ty: "Movie", grants: ["emma"] },
  { id: 15, t: "Back to the Future", y: 1985, g: "Comedy", r: "PG", ty: "Movie", grants: [], col: "c-bttf" },
  { id: 16, t: "Alien", y: 1979, g: "Horror", r: "R", ty: "Movie", grants: [] },
  { id: 17, t: "Song of the Sea", y: 2014, g: "Animation", r: "PG", ty: "Movie", grants: [] },
  { id: 18, t: "The Blue Planet", y: 2001, g: "Documentary", r: "G", ty: "Series", grants: [] },
  { id: 19, t: "Back to the Future Part II", y: 1989, g: "Comedy", r: "PG", ty: "Movie", grants: [], col: "c-bttf" },
  { id: 20, t: "Back to the Future Part III", y: 1990, g: "Comedy", r: "PG", ty: "Movie", grants: [], col: "c-bttf" },
  { id: 21, t: "The Lost World", y: 1997, g: "Adventure", r: "PG-13", ty: "Movie", grants: [], col: "c-jp" },
];

const COLLECTIONS = [
  { id: "c-ghibli", t: "Studio Ghibli", y: 1988, g: "Animation", ty: "Collection" },
  { id: "c-bttf", t: "Back to the Future", y: 1985, g: "Comedy", ty: "Collection" },
  { id: "c-jp", t: "Jurassic Park", y: 1993, g: "Adventure", ty: "Collection" },
];

const RANK = { G: 0, "TV-Y": 0, "TV-Y7": 1, PG: 2, "TV-PG": 2, "PG-13": 3, "TV-14": 3, R: 5 };

const membersOf = (colId) => ITEMS.filter((i) => i.col === colId);
const collectionOf = (item) => COLLECTIONS.find((c) => c.id === item.col) || null;

/* collections inherit the strictest-looking rating of their members */
const COL_ROWS = COLLECTIONS.map((c) => {
  const m = membersOf(c.id);
  return { ...c, r: m.reduce((a, b) => (RANK[b.r] > RANK[a] ? b.r : a), "G"), members: m };
});

/* --------------------------------------------------------------- helpers */

const hueOf = (s) => {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360;
  return h;
};

const Icon = ({ d, size = 24 }) => (
  <svg viewBox="0 0 24 24" width={size} height={size} fill="currentColor" aria-hidden="true">
    <path d={d} />
  </svg>
);

const P = {
  people: "M12 12q-1.65 0-2.825-1.175Q8 9.65 8 8q0-1.65 1.175-2.825Q10.35 4 12 4q1.65 0 2.825 1.175Q16 6.35 16 8q0 1.65-1.175 2.825Q13.65 12 12 12Zm-8 8v-2.8q0-.85.437-1.563.438-.712 1.163-1.087 1.55-.775 3.15-1.163Q10.35 13 12 13t3.25.387q1.6.388 3.15 1.163.725.375 1.163 1.087Q20 16.35 20 17.2V20Z",
  video: "M4 20q-.825 0-1.412-.587Q2 18.825 2 18V6q0-.825.588-1.413Q3.175 4 4 4h16q.825 0 1.413.587Q22 5.175 22 6v12q0 .825-.587 1.413Q20.825 20 20 20Zm5.5-3.5 6-4.5-6-4.5Z",
  history: "M13 21q-3.15 0-5.575-1.912Q5 17.175 4.25 14.2q-.125-.5.163-.9.287-.4.812-.5.475-.075.875.187.4.263.55.738.575 2.2 2.375 3.638Q10.825 19 13 19q2.5 0 4.25-1.75T19 13q0-2.5-1.75-4.25T13 7h-.15l.85.85q.3.3.288.7-.013.4-.313.7-.3.275-.7.287-.4.013-.7-.287L9.7 7.7q-.15-.15-.212-.325Q9.425 7.2 9.425 7t.063-.375Q9.55 6.45 9.7 6.3l2.575-2.575q.275-.275.687-.275.413 0 .713.3.275.3.275.712 0 .413-.275.688l-.825.85H13q3.35 0 5.675 2.325Q21 10.65 21 14q0 3.35-2.325 5.675Q16.35 22 13 22Z",
  settings: "m9.25 22-.4-3.2q-.325-.125-.612-.3-.288-.175-.563-.375L4.7 19.375l-2.75-4.75 2.575-1.95Q4.5 12.5 4.5 12.338v-.675q0-.163.025-.338L1.95 9.375l2.75-4.75 2.975 1.25q.275-.2.575-.375.3-.175.6-.3L9.25 2h5.5l.4 3.2q.325.125.613.3.287.175.562.375l2.975-1.25 2.75 4.75-2.575 1.95q.025.175.025.338v.674q0 .163-.05.338l2.575 1.95-2.75 4.75-2.95-1.25q-.275.2-.575.375-.3.175-.6.3l-.4 3.2ZM12 15.5q1.45 0 2.475-1.025Q15.5 13.45 15.5 12q0-1.45-1.025-2.475Q13.45 8.5 12 8.5q-1.475 0-2.488 1.025Q8.5 10.55 8.5 12q0 1.45 1.012 2.475Q10.525 15.5 12 15.5Z",
  check: "M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41Z",
  back: "M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20Z",
  add: "M11 13H5v-2h6V5h2v6h6v2h-6v6h-2Z",
  down: "M12 15.4 6.6 10l1.4-1.4 4 4 4-4L17.4 10Z",
  right: "M9.4 18 8 16.6l4.6-4.6L8 7.4 9.4 6l6 6Z",
  stack: "M3 21v-2h18v2Zm0-4v-2h18v2Zm2-4q-.825 0-1.412-.587Q3 11.825 3 11V6q0-.825.588-1.412Q4.175 4 5 4h14q.825 0 1.413.588Q21 5.175 21 6v5q0 .825-.587 1.413Q19.825 13 19 13Z",
  shield: "M12 22q-3.475-.875-5.738-3.988Q4 14.9 4 11.1V5l8-3 8 3v6.1q0 3.8-2.262 6.912Q15.475 21.125 12 22Z",
  block: "M12 22q-2.075 0-3.9-.788-1.825-.787-3.175-2.137-1.35-1.35-2.137-3.175Q2 14.075 2 12t.788-3.9q.787-1.825 2.137-3.175 1.35-1.35 3.175-2.138Q9.925 2 12 2t3.9.787q1.825.788 3.175 2.138 1.35 1.35 2.138 3.175Q22 9.925 22 12t-.787 3.9q-.788 1.825-2.138 3.175-1.35 1.35-3.175 2.137Q14.075 22 12 22Zm0-2q1.35 0 2.6-.437 1.25-.438 2.3-1.263L5.7 7.1q-.8 1.05-1.25 2.3Q4 10.65 4 12q0 3.35 2.325 5.675Q8.65 20 12 20Z",
  tune: "M11 21v-6h2v2h8v2h-8v2Zm-8-2v-2h6v2Zm4-4v-2H3v-2h4V9h2v6Zm4-2v-2h10v2Zm4-4V3h2v2h4v2h-4v2Z",
};

const Mark = ({ size = 64 }) => (
  <svg viewBox="0 0 64 64" width={size} height={size} aria-label={`${APP_NAME} logo`}>
    <defs>
      <linearGradient id="gf-body" x1="0" y1="0" x2="0.6" y2="1">
        <stop offset="0" stopColor="#EADDFF" />
        <stop offset="1" stopColor="#8C6ED4" />
      </linearGradient>
    </defs>
    <path d="M5 32c0-7 4-13 8.5-15.5v31C9 45 5 39 5 32Z" fill="#B69DF8" />
    <path d="M33 15c-2.5-7 1.5-12 8.5-12-1.5 5 .5 8.5 4 10.5Z" fill="#B69DF8" />
    <path d="M30 47c-2 5 1 8 6 8-1-3.5 0-5.5 2-7Z" fill="#9A7FE0" />
    <ellipse cx="36" cy="32" rx="24" ry="17.5" fill="url(#gf-body)" />
    <circle cx="46.5" cy="26.5" r="6.2" fill="#241C36" />
    <circle cx="48.8" cy="24.2" r="2.2" fill="#FFFFFF" />
    <path d="M43 38.5q4.5 3.5 9 0" stroke="#241C36" strokeWidth="2.6" fill="none" strokeLinecap="round" />
    <circle cx="24" cy="30" r="2.6" fill="#FFFFFF" opacity=".5" />
    <circle cx="20" cy="36" r="1.7" fill="#FFFFFF" opacity=".35" />
  </svg>
);

/* Placeholder for the Jellyfin user avatar: /Users/{id}/Images/Primary */
const Avatar = ({ kid, size = 40, ring }) => (
  <div
    className={ring ? "m3-avatar ring" : "m3-avatar"}
    style={{
      width: size, height: size, fontSize: size * 0.42,
      background: `hsl(${kid.hue} 32% 26%)`, color: `hsl(${kid.hue} 70% 82%)`,
      "--ring": `hsl(${kid.hue} 60% 66%)`,
    }}
  >
    {kid.name[0]}
  </div>
);

const Progress = ({ value, total, hue }) => (
  <div className="m3-progress">
    <div className="m3-progress-track" />
    <div
      className="m3-progress-bar"
      style={{ width: `${Math.max(2, (value / total) * 100)}%`, background: `hsl(${hue} 60% 66%)` }}
    />
  </div>
);

const Poster = ({ item }) => {
  const h = hueOf(item.t);
  return (
    <div
      className="m3-poster"
      style={{ background: `linear-gradient(158deg, hsl(${h} 34% 34%), hsl(${(h + 44) % 360} 30% 17%))` }}
    >
      <span className="m3-poster-t">{item.t}</span>
      <span className="m3-poster-y">{item.y}</span>
    </div>
  );
};

const Cover = ({ item }) =>
  item.ty === "Collection" ? (
    <div className="m3-stackwrap">
      <span className="m3-stack-b2" />
      <span className="m3-stack-b1" />
      <Poster item={item} />
    </div>
  ) : (
    <Poster item={item} />
  );

const Switch = ({ on, onClick }) => (
  <button className={on ? "m3-switch on" : "m3-switch"} onClick={onClick} role="switch" aria-checked={on}>
    <span className="m3-switch-thumb">{on && <Icon d={P.check} size={14} />}</span>
  </button>
);

/* --------------------------------------------------------------- screens */

function SignIn({ go }) {
  const [mode, setMode] = useState("quick");
  return (
    <div className="m3-body m3-signin">
      <div className="m3-brand">
        <Mark size={72} />
        <h1 className="m3-display">{APP_NAME}</h1>
        <p className="m3-body-medium m3-onvar">Hand-pick what the kids can watch</p>
      </div>

      <div className="m3-textfield">
        <span className="m3-textfield-label">Your server</span>
        <span className="m3-textfield-value">https://jelly.maison.lan</span>
      </div>

      <div className="m3-tabs">
        <button className={mode === "quick" ? "on" : ""} onClick={() => setMode("quick")}>Quick Connect</button>
        <button className={mode === "pw" ? "on" : ""} onClick={() => setMode("pw")}>Password</button>
      </div>

      {mode === "quick" ? (
        <>
          <p className="m3-body-medium m3-onvar">Type this into Jellyfin under Quick Connect.</p>
          <div className="m3-code">
            {["4", "7", "2", "9", "1", "3"].map((n, i) => <span key={i}>{n}</span>)}
          </div>
          <div className="m3-indeterminate"><i /></div>
          <p className="m3-label m3-onvar">Waiting for you to say yes…</p>
        </>
      ) : (
        <>
          <div className="m3-textfield">
            <span className="m3-textfield-label">Admin user</span>
            <span className="m3-textfield-value">marc</span>
          </div>
          <div className="m3-textfield">
            <span className="m3-textfield-label">Password</span>
            <span className="m3-textfield-value">••••••••••</span>
          </div>
        </>
      )}

      <button className="m3-filled" onClick={() => go("browse")}>Let me in</button>
      <p className="m3-label m3-onvar m3-center">
        Needs an admin account — labels get written back to your library.
      </p>
    </div>
  );
}

function Browse({ kidId, setKidId, openSheet, openMenu, filters, grants }) {
  const kid = MANAGED.find((k) => k.id === kidId) || null;
  const { type, genre, decade, safe, hideShared } = filters;

  const grantedOn = (it) => [...it.grants, ...grants.filter((g) => g.item === it.id).map((g) => g.kid)];
  const colGrants = (c) => MANAGED
    .filter((k) => c.members.every((m) => grantedOn(m).includes(k.id)))
    .map((k) => k.id);

  const rows = useMemo(() => {
    const all = [...COL_ROWS, ...ITEMS];
    return all.filter((i) => {
      if (type !== "All" && i.ty !== type) return false;
      if (genre !== "All" && i.g !== genre) return false;
      if (decade !== "All" && `${Math.floor(i.y / 10) * 10}s` !== decade) return false;
      if (kid) {
        const has = i.ty === "Collection" ? colGrants(i).includes(kid.id) : grantedOn(i).includes(kid.id);
        if (hideShared && has) return false;
        if (safe && RANK[i.r] > RANK[kid.cap]) return false;
      }
      return true;
    });
  }, [type, genre, decade, safe, hideShared, kid, grants]);

  const FilterChip = ({ label, value, onClick, active }) => (
    <button className={active ? "m3-chip on" : "m3-chip"} onClick={onClick}>
      {active ? value : label}
      <Icon d={P.down} size={18} />
    </button>
  );

  return (
    <div className="m3-body">
      <div className="m3-forwhom">
        <span className="m3-overline m3-flush">Picking for</span>
        <div className="m3-kidrow">
          {MANAGED.map((k) => {
            const on = k.id === kidId;
            return (
              <button
                key={k.id}
                className={on ? "m3-kidpick on" : "m3-kidpick"}
                onClick={() => setKidId(on ? null : k.id)}
              >
                <Avatar kid={k} size={44} ring={on} />
                <span className="m3-label">{k.name}</span>
              </button>
            );
          })}
          <button
            className={kidId === null ? "m3-kidpick on" : "m3-kidpick"}
            onClick={() => setKidId(null)}
          >
            <span className="m3-kidpick-all"><Icon d={P.people} size={22} /></span>
            <span className="m3-label">Everyone</span>
          </button>
        </div>
      </div>

      <div className="m3-filterbar">
        <button className="m3-icon-chip" onClick={() => openMenu("all")}>
          <Icon d={P.tune} size={20} />
        </button>
        <div className="m3-chiprow">
          <FilterChip label="Type" value={type} active={type !== "All"} onClick={() => openMenu("type")} />
          <FilterChip label="Genre" value={genre} active={genre !== "All"} onClick={() => openMenu("genre")} />
          <FilterChip label="Decade" value={decade} active={decade !== "All"} onClick={() => openMenu("decade")} />
          {kid && (
            <button className={safe ? "m3-chip on" : "m3-chip"} onClick={() => filters.set("safe", !safe)}>
              {safe && <Icon d={P.check} size={17} />}
              Up to {kid.cap}
            </button>
          )}
        </div>
      </div>

      <div className="m3-resultline">
        <span className="m3-body-medium m3-onvar">
          {kid ? <>{rows.length} things {kid.name} hasn't got yet</> : <>{rows.length} titles</>}
        </span>
        {kid && (
          <button className="m3-text-btn m3-tight" onClick={() => filters.set("hideShared", !hideShared)}>
            {hideShared ? "Show shared" : "Hide shared"}
          </button>
        )}
      </div>

      <div className="m3-grid">
        {rows.map((it) => {
          const isCol = it.ty === "Collection";
          const gs = isCol ? colGrants(it) : grantedOn(it);
          const mine = kid && gs.includes(kid.id);
          return (
            <button key={it.id} className="m3-tile" onClick={() => openSheet(it)}>
              <div className="m3-poster-wrap">
                <Cover item={it} />
                {mine && <span className="m3-badge"><Icon d={P.check} size={14} /></span>}
                {isCol && (
                  <span className="m3-colbadge">
                    <Icon d={P.stack} size={12} />{it.members.length}
                  </span>
                )}
              </div>
              <span className="m3-body-medium m3-tile-t">{it.t}</span>
              <span className="m3-label m3-onvar">
                {isCol ? `Collection · ${it.r}` : `${it.r} · ${it.g}`}
              </span>
              <span className="m3-tile-dots">
                {gs.length === 0
                  ? <span className="m3-label m3-dim">Nobody yet</span>
                  : gs.map((id) => <Avatar key={id} size={20} kid={KIDS.find((k) => k.id === id)} />)}
              </span>
            </button>
          );
        })}
      </div>
      <div className="m3-spacer" />
    </div>
  );
}

function Kids({ go, setKidId, grants }) {
  const extra = (id) => grants.filter((g) => g.kid === id).length;
  const total = LIBRARIES.reduce((a, l) => a + l.total, 0);
  return (
    <div className="m3-body">
      <p className="m3-overline m3-flush">Kept to a shortlist</p>
      {MANAGED.map((k) => {
        const seen = Object.values(k.libs).reduce((a, b) => a + b, 0) + extra(k.id);
        return (
          <button key={k.id} className="m3-card" onClick={() => { setKidId(k.id); go("kid"); }}>
            <div className="m3-card-top">
              <Avatar kid={k} />
              <div className="m3-card-headline">
                <span className="m3-title">{k.name}</span>
                <span className="m3-body-medium m3-onvar">Age {k.age} · up to {k.cap}</span>
              </div>
              <span className={k.mode === "allow" ? "m3-assist m3-assist-ok" : "m3-assist m3-assist-warn"}>
                <Icon d={k.mode === "allow" ? P.shield : P.block} size={16} />
                {k.mode === "allow" ? "Allow-list" : "Block-list"}
              </span>
            </div>
            <div className="m3-tagwrap">
              {k.tags.map((t) => <code key={t} className="m3-code-chip">{t}</code>)}
            </div>
            <Progress value={seen} total={total} hue={k.hue} />
            <span className="m3-label m3-onvar">
              {seen.toLocaleString()} of {total.toLocaleString()} things visible
            </span>
          </button>
        );
      })}

      <p className="m3-overline">No shortlist set</p>
      {KIDS.filter((k) => !k.mode).map((k) => (
        <div key={k.id} className="m3-list-item">
          <Avatar kid={k} />
          <div className="m3-list-text">
            <span className="m3-body-large">{k.name}</span>
            <span className="m3-body-medium m3-onvar">
              {k.admin ? "Administrator — sees the lot" : "No allowed or blocked tags yet"}
            </span>
          </div>
          {!k.admin && <button className="m3-text-btn">Set up</button>}
        </div>
      ))}
      <div className="m3-spacer" />
    </div>
  );
}

function KidDetail({ kid, grants }) {
  const extra = grants.filter((g) => g.kid === kid.id).length;
  const seen = Object.values(kid.libs).reduce((a, b) => a + b, 0) + extra;
  const total = LIBRARIES.reduce((a, l) => a + l.total, 0);
  return (
    <div className="m3-body">
      <div className="m3-hero" style={{ background: `hsl(${kid.hue} 26% 18%)` }}>
        <Avatar kid={kid} size={56} />
        <span className="m3-hero-num" style={{ color: `hsl(${kid.hue} 62% 76%)` }}>
          {seen.toLocaleString()}
        </span>
        <span className="m3-body-medium m3-onvar">of {total.toLocaleString()} things visible</span>
        <Progress value={seen} total={total} hue={kid.hue} />
        <p className="m3-body-medium m3-hero-note">
          {kid.mode === "allow"
            ? <>Only sees what's tagged <code className="m3-code-chip">{kid.tags[0]}</code>.</>
            : <>Sees everything except {kid.tags.map((t) => <code key={t} className="m3-code-chip">{t}</code>)}.</>}
        </p>
      </div>

      <p className="m3-overline">Libraries</p>
      {LIBRARIES.map((l) => {
        const v = kid.libs[l.id] ?? 0;
        const on = kid.enabled.includes(l.id);
        return (
          <div key={l.id} className={on ? "m3-lib" : "m3-lib off"}>
            <div className="m3-lib-row">
              <span className="m3-body-large">{l.name}</span>
              <span className="m3-label m3-onvar">
                {on ? `${v.toLocaleString()} / ${l.total.toLocaleString()}` : "Locked out"}
              </span>
            </div>
            {on && <Progress value={v} total={l.total} hue={kid.hue} />}
          </div>
        );
      })}
      <div className="m3-spacer" />
    </div>
  );
}

function Activity({ grants, prefix }) {
  const tagFor = (id) => (prefix ? `kids-${id}` : id);
  const base = [
    { k: "emma", t: "Ratatouille", w: "2 h ago", op: "add" },
    { k: "noah", t: "Back to the Future", w: "Yesterday", op: "add", n: 3 },
    { k: "lea", t: "Alien", w: "Yesterday", op: "block" },
    { k: "emma", t: "Bluey", w: "3 days ago", op: "add" },
  ];
  const live = grants
    .map((g) => ({ k: g.kid, t: ITEMS.find((i) => i.id === g.item).t, w: "Just now", op: "add" }))
    .reverse();

  return (
    <div className="m3-body">
      {[...live, ...base].map((e, i) => {
        const kid = KIDS.find((k) => k.id === e.k);
        return (
          <div key={i} className="m3-list-item">
            <Avatar kid={kid} size={40} />
            <div className="m3-list-text">
              <span className="m3-body-large">
                {e.t}{e.n ? ` + ${e.n - 1} more` : ""}
              </span>
              <span className="m3-body-medium m3-onvar">
                {e.op === "add" ? "Handed to" : "Taken from"} {kid.name} · {e.w}
              </span>
            </div>
            {e.w === "Just now"
              ? <button className="m3-text-btn">Undo</button>
              : <code className="m3-code-chip">{e.op === "add" ? tagFor(kid.id) : "horror"}</code>}
          </div>
        );
      })}
      <div className="m3-spacer" />
    </div>
  );
}

function Settings({ s, set }) {
  const Row = ({ title, sub, trailing, dim }) => (
    <button className={dim ? "m3-setting dim" : "m3-setting"}>
      <div className="m3-list-text">
        <span className="m3-body-large">{title}</span>
        {sub && <span className="m3-body-medium m3-onvar">{sub}</span>}
      </div>
      {trailing}
    </button>
  );

  const example = s.prefix ? "kids-emma" : "emma";

  return (
    <div className="m3-body">
      <p className="m3-overline m3-flush">Server</p>
      <Row title="jelly.maison.lan" sub="Signed in as marc · admin"
        trailing={<span className="m3-text-btn">Sign out</span>} />
      <Row title="Refresh library cache" sub="Last synced 12 minutes ago"
        trailing={<Icon d={P.right} size={20} />} />

      <p className="m3-overline">Labels</p>
      <Row title="Add a prefix to tags"
        sub={`Tags will read ${example}`}
        trailing={<Switch on={s.prefix} onClick={() => set("prefix", !s.prefix)} />} />
      <Row title="The prefix"
        sub={s.prefix ? "Keeps Garfin's tags apart from your own" : "Off — tags use the account name alone"}
        dim={!s.prefix}
        trailing={<code className="m3-code-chip">{s.prefix ? "kids-" : "none"}</code>} />
      <Row title="Cascade to episodes" sub="Tag seasons and episodes too, not just the series"
        trailing={<Switch on={s.cascade} onClick={() => set("cascade", !s.cascade)} />} />
      <Row title="Cascade to collection members" sub="Tagging a collection tags every film inside it"
        trailing={<Switch on={s.colCascade} onClick={() => set("colCascade", !s.colCascade)} />} />
      <Row title="When a film belongs to a collection"
        sub="Ask each time, or always keep sets together"
        trailing={<span className="m3-value">Ask each time</span>} />
      <Row title="Refresh metadata after write" sub="Slower, but the change shows up straight away"
        trailing={<Switch on={s.refresh} onClick={() => set("refresh", !s.refresh)} />} />

      <p className="m3-overline">Picking</p>
      <Row title="Start on" sub="Which face is selected when you open the app"
        trailing={<span className="m3-value">Emma</span>} />
      <Row title="Hide what's already shared" sub="Turns the grid into a to-do list"
        trailing={<Switch on={s.hideShared} onClick={() => set("hideShared", !s.hideShared)} />} />
      <Row title="Respect the age cap by default" sub="Hides anything above a child's rating limit"
        trailing={<Switch on={s.safeDefault} onClick={() => set("safeDefault", !s.safeDefault)} />} />
      <Row title="Libraries to browse" sub="Movies, TV Shows, Documentaries"
        trailing={<Icon d={P.right} size={20} />} />

      <p className="m3-overline">Looks</p>
      <Row title="Theme" trailing={<span className="m3-value">Follow system</span>} />
      <Row title="Use my wallpaper colours" sub="Material You, Android 12 and up"
        trailing={<Switch on={s.dynamic} onClick={() => set("dynamic", !s.dynamic)} />} />
      <Row title="Poster size" trailing={<span className="m3-value">Medium</span>} />

      <p className="m3-overline">About</p>
      <div className="m3-about">
        <Mark size={44} />
        <div className="m3-list-text">
          <span className="m3-body-large">{APP_NAME} 0.1.0</span>
          <span className="m3-body-medium m3-onvar">
            Free software under the GNU GPL v3. Not affiliated with the Jellyfin project.
          </span>
        </div>
      </div>
      <Row title="Source code" sub="Patches welcome" trailing={<Icon d={P.right} size={20} />} />
      <Row title="Licences" sub="GPL-3.0 · Fredoka and Nunito under the SIL OFL 1.1"
        trailing={<Icon d={P.right} size={20} />} />
      <div className="m3-spacer" />
    </div>
  );
}

/* ------------------------------------------------------------- overlays */

function MenuSheet({ which, filters, close }) {
  const genres = ["All", ...new Set([...ITEMS, ...COL_ROWS].map((i) => i.g))];
  const decades = ["All", ...[...new Set(ITEMS.map((i) => `${Math.floor(i.y / 10) * 10}s`))].sort()];

  const GROUPS = {
    type: { title: "Type", key: "type", options: ["All", "Movie", "Series", "Collection"] },
    genre: { title: "Genre", key: "genre", options: genres },
    decade: { title: "Decade", key: "decade", options: decades },
  };
  const groups = which === "all" ? ["type", "genre", "decade"] : [which];

  return (
    <div className="m3-scrim" onClick={close}>
      <div className="m3-sheet" onClick={(e) => e.stopPropagation()}>
        <div className="m3-handle" />
        {groups.map((gk) => {
          const g = GROUPS[gk];
          return (
            <div key={gk} className="m3-menugroup">
              <p className="m3-overline m3-flush">{g.title}</p>
              {g.options.map((o) => {
                const on = filters[g.key] === o;
                return (
                  <button key={o} className="m3-menuitem"
                    onClick={() => { filters.set(g.key, o); if (which !== "all") close(); }}>
                    <span className={on ? "m3-radio on" : "m3-radio"} />
                    <span className="m3-body-large">{o}</span>
                  </button>
                );
              })}
            </div>
          );
        })}
        {which === "all" && (
          <div className="m3-sheet-actions">
            <button className="m3-text-btn" onClick={() => {
              filters.set("type", "All"); filters.set("genre", "All"); filters.set("decade", "All");
            }}>Reset</button>
            <button className="m3-filled" onClick={close}>Done</button>
          </div>
        )}
      </div>
    </div>
  );
}

function AssignSheet({ item, close, grants, request, focusKid, prefix }) {
  const isCol = item.ty === "Collection";
  const tagFor = (id) => (prefix ? `kids-${id}` : id);

  const grantedOn = (it) => [...it.grants, ...grants.filter((g) => g.item === it.id).map((g) => g.kid)];
  const current = isCol
    ? MANAGED.filter((k) => item.members.every((m) => grantedOn(m).includes(k.id))).map((k) => k.id)
    : grantedOn(item);

  const [sel, setSel] = useState(current);
  const added = sel.filter((s) => !current.includes(s));
  const removed = current.filter((c) => !sel.includes(c));
  const dirty = added.length > 0 || removed.length > 0;
  const order = focusKid
    ? [...MANAGED].sort((a, b) => (a.id === focusKid ? -1 : b.id === focusKid ? 1 : 0))
    : MANAGED;
  const col = !isCol ? collectionOf(item) : null;

  return (
    <div className="m3-scrim" onClick={close}>
      <div className="m3-sheet" onClick={(e) => e.stopPropagation()}>
        <div className="m3-handle" />
        <div className="m3-sheet-head">
          <div className="m3-sheet-poster"><Cover item={item} /></div>
          <div>
            <h2 className="m3-title-lg">{item.t}</h2>
            <p className="m3-body-medium m3-onvar">
              {isCol
                ? `Collection · ${item.members.length} films · up to ${item.r}`
                : `${item.y} · ${item.g} · ${item.r}`}
            </p>
          </div>
        </div>

        {isCol && (
          <div className="m3-note">
            <Icon d={P.stack} size={18} />
            <span className="m3-body-medium">
              Labels land on all {item.members.length} films inside, not on the collection alone.
            </span>
          </div>
        )}
        {col && (
          <div className="m3-note soft">
            <Icon d={P.stack} size={18} />
            <span className="m3-body-medium">
              Part of {col.t} — {membersOf(col.id).length} films in the set.
            </span>
          </div>
        )}

        <p className="m3-overline">Hand it to</p>
        {order.map((k) => {
          const on = sel.includes(k.id);
          const tooOld = RANK[item.r] > RANK[k.cap];
          return (
            <button key={k.id} className={on ? "m3-select on" : "m3-select"}
              onClick={() => setSel(on ? sel.filter((s) => s !== k.id) : [...sel, k.id])}>
              <Avatar kid={k} />
              <div className="m3-list-text">
                <span className="m3-body-large">{k.name}</span>
                {tooOld && (
                  <span className="m3-body-medium m3-warn">
                    {isCol ? `Some films are over ${k.name}'s ${k.cap} limit` : `Over ${k.name}'s ${k.cap} limit`}
                  </span>
                )}
              </div>
              <span className={on ? "m3-checkbox on" : "m3-checkbox"}>
                {on && <Icon d={P.check} size={16} />}
              </span>
            </button>
          );
        })}

        {dirty && (
          <div className="m3-diff">
            <span className="m3-overline m3-flush">
              Tags {isCol ? `on each of the ${item.members.length} films` : "on this item"}
            </span>
            <div className="m3-tagwrap">
              {added.map((a) => <code key={a} className="m3-code-chip add">+ {tagFor(a)}</code>)}
              {removed.map((r) => <code key={r} className="m3-code-chip rm">− {tagFor(r)}</code>)}
            </div>
          </div>
        )}

        <div className="m3-sheet-actions">
          <button className="m3-text-btn" onClick={close}>Cancel</button>
          <button className="m3-filled" disabled={!dirty} onClick={() => request(item, added, removed)}>
            Apply labels
          </button>
        </div>
      </div>
    </div>
  );
}

/* the collection question */
function CollectionDialog({ pending, resolve, cancel }) {
  const col = collectionOf(pending.item);
  const members = membersOf(col.id);
  const others = members.filter((m) => m.id !== pending.item.id);
  const names = pending.added.map((a) => KIDS.find((k) => k.id === a).name).join(" and ");

  return (
    <div className="m3-scrim center" onClick={cancel}>
      <div className="m3-dialog" onClick={(e) => e.stopPropagation()}>
        <span className="m3-dialog-icon"><Icon d={P.stack} size={24} /></span>
        <h3 className="m3-title-lg m3-center">Keep the set together?</h3>
        <p className="m3-body-medium m3-onvar m3-center">
          {pending.item.t} belongs to {col.t}. {names} could have the other{" "}
          {others.length === 1 ? "film" : `${others.length} films`} too.
        </p>
        <div className="m3-dialog-list">
          {others.map((m) => (
            <div key={m.id} className="m3-dialog-row">
              <span className="m3-body-medium">{m.t}</span>
              <code className="m3-code-chip">{m.r}</code>
            </div>
          ))}
        </div>
        <div className="m3-dialog-actions">
          <button className="m3-text-btn" onClick={() => resolve(false)}>Just this one</button>
          <button className="m3-filled" onClick={() => resolve(true)}>
            All {members.length}
          </button>
        </div>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------- app */

export default function App() {
  const [screen, setScreen] = useState("signin");
  const [kidId, setKidId] = useState("emma");
  const [sheet, setSheet] = useState(null);
  const [menu, setMenu] = useState(null);
  const [pending, setPending] = useState(null);
  const [grants, setGrants] = useState([]);
  const [snack, setSnack] = useState(null);

  const [f, setF] = useState({ type: "All", genre: "All", decade: "All", safe: true, hideShared: true });
  const filters = { ...f, set: (k, v) => setF((s) => ({ ...s, [k]: v })) };

  const [prefs, setPrefs] = useState({
    prefix: true, cascade: true, colCascade: true, refresh: false,
    hideShared: true, safeDefault: true, dynamic: true,
  });
  const setPref = (k, v) => setPrefs((s) => ({ ...s, [k]: v }));

  const kid = MANAGED.find((k) => k.id === kidId) || null;

  const commit = (targets, added, removed, label) => {
    setGrants((g) => {
      const ids = targets.map((t) => t.id);
      const cleaned = g.filter((x) => !(ids.includes(x.item) && removed.includes(x.kid)));
      const fresh = [];
      targets.forEach((t) => added.forEach((a) => {
        if (!cleaned.some((x) => x.item === t.id && x.kid === a)) fresh.push({ item: t.id, kid: a });
      }));
      return [...cleaned, ...fresh];
    });
    const names = added.map((a) => KIDS.find((k) => k.id === a).name).join(" and ");
    setSnack(added.length ? `${label} — on ${names}'s shelf` : `${label} — taken back`);
    setTimeout(() => setSnack(null), 4000);
  };

  /* the sheet asks; the app decides whether a question is owed first */
  const request = (item, added, removed) => {
    setSheet(null);
    if (item.ty === "Collection") {
      commit(item.members, added, removed, `${item.t} · ${item.members.length} films`);
      return;
    }
    if (item.col && added.length > 0) {
      setPending({ item, added, removed });
      return;
    }
    commit([item], added, removed, item.t);
  };

  const resolve = (whole) => {
    const { item, added, removed } = pending;
    setPending(null);
    if (whole) {
      const members = membersOf(item.col);
      commit(members, added, removed, `${collectionOf(item).t} · ${members.length} films`);
    } else {
      commit([item], added, removed, item.t);
    }
  };

  const NAV = [
    ["browse", "Library", P.video],
    ["kids", "Kids", P.people],
    ["activity", "Activity", P.history],
    ["settings", "Settings", P.settings],
  ];

  const JUMPS = [
    ["signin", "Sign in"], ["browse", "Library"], ["kids", "Kids"],
    ["kid", "Kid detail"], ["activity", "Activity"], ["settings", "Settings"],
  ];

  const onKid = screen === "kid";
  const title = onKid ? (kid ? kid.name : "Kid")
    : screen === "browse" ? "Library"
    : screen === "kids" ? "Kids"
    : screen === "activity" ? "Activity" : "Settings";

  return (
    <div className="m3-root">
      <style>{CSS}</style>

      <div className="m3-stage">
        <div className="m3-walk">
          <span className="m3-overline m3-flush">Walk through</span>
          <div className="m3-chiprow">
            {JUMPS.map(([id, label]) => (
              <button key={id} className={screen === id ? "m3-chip on" : "m3-chip"}
                onClick={() => { if (id === "kid" && !kid) setKidId("emma"); setScreen(id); }}>
                {screen === id && <Icon d={P.check} size={17} />}
                {label}
              </button>
            ))}
          </div>
          <span className="m3-hint">
            Tap “Back to the Future” in the grid to see the collection question.
          </span>
        </div>

        <div className="m3-device">
          <div className="m3-statusbar"><span>9:41</span><span>▮▮▮ ⌁ ▰</span></div>

          {screen !== "signin" && (
            <div className="m3-appbar">
              {onKid && (
                <button className="m3-icon-btn" onClick={() => setScreen("kids")}>
                  <Icon d={P.back} size={22} />
                </button>
              )}
              <span className="m3-appbar-title">{title}</span>
              {screen === "browse" && <span className="m3-appbar-mark"><Mark size={30} /></span>}
            </div>
          )}

          <div className="m3-viewport">
            {screen === "signin" && <SignIn go={setScreen} />}
            {screen === "browse" && (
              <Browse kidId={kidId} setKidId={setKidId} openSheet={setSheet}
                openMenu={setMenu} filters={filters} grants={grants} />
            )}
            {screen === "kids" && <Kids go={setScreen} setKidId={setKidId} grants={grants} />}
            {screen === "kid" && kid && <KidDetail kid={kid} grants={grants} />}
            {screen === "activity" && <Activity grants={grants} prefix={prefs.prefix} />}
            {screen === "settings" && <Settings s={prefs} set={setPref} />}

            {onKid && (
              <button className="m3-fab" onClick={() => setScreen("browse")}>
                <Icon d={P.add} size={22} />Add titles
              </button>
            )}

            {menu && <MenuSheet which={menu} filters={filters} close={() => setMenu(null)} />}
            {sheet && (
              <AssignSheet item={sheet} close={() => setSheet(null)} grants={grants}
                request={request} focusKid={kidId} prefix={prefs.prefix} />
            )}
            {pending && (
              <CollectionDialog pending={pending} resolve={resolve} cancel={() => setPending(null)} />
            )}

            {snack && (
              <div className="m3-snackbar">
                <span>{snack}</span>
                <button className="m3-snack-action">Undo</button>
              </div>
            )}
          </div>

          {screen !== "signin" && (
            <nav className="m3-navbar">
              {NAV.map(([id, label, d]) => {
                const active = screen === id || (id === "kids" && onKid);
                return (
                  <button key={id} className={active ? "m3-navitem on" : "m3-navitem"} onClick={() => setScreen(id)}>
                    <span className="m3-nav-pill"><Icon d={d} size={22} /></span>
                    <span className="m3-nav-label">{label}</span>
                  </button>
                );
              })}
            </nav>
          )}
        </div>
      </div>

      <Spec />
    </div>
  );
}

/* ------------------------------------------------------------------ spec */

const SPEC = [
  {
    s: "Collections",
    b: [
      "A Jellyfin BoxSet is a container, and tagging the container does nothing for the child — the films inside are what the policy filters. So tagging a collection always writes to every member.",
      "Collections are browsable in their own right: they appear in the grid with a stacked cover, a count badge, and the strictest rating found among their members.",
      "A collection counts as 'shared' with a child only when every film inside is. A half-shared set stays in the to-do list rather than looking finished.",
      "Tag a single film that belongs to a set and the app asks once, listing the other members and their ratings, then either keeps the set together or writes just the one.",
      "The question only fires on additions. Removing a label from one film never silently strips the rest — that would make an unshare unpredictable.",
      "The preference has three states: ask each time, always the whole set, or always just the item. Ask is the default because 'Jurassic Park' and 'Jurassic Park III' are not the same decision.",
    ],
    api: [
      "GET /Items?IncludeItemTypes=BoxSet&Recursive=true&Fields=Tags → the collections",
      "GET /Items?parentId={boxsetId} → members (a film can belong to several sets)",
      "Write per member: GET /Users/{admin}/Items/{id}, modify Tags, POST /Items/{id}",
      "Batch the writes and roll back together if one fails, or the set ends up half-tagged",
    ],
  },
  {
    s: "Tags and the optional prefix",
    b: [
      "The prefix is off-by-choice: some servers already use bare account names as tags, and forcing kids- would orphan every label they have.",
      "With the prefix on, tags read kids-emma; with it off, emma. The setting rewrites what the assign sheet previews, so you always see what will actually be written.",
      "Changing the prefix does not retag the library — the app offers a one-off migration instead of silently rewriting thousands of items.",
      "Cascade to episodes and cascade to collection members are separate switches: one walks down a series, the other across a set.",
      "Every write is previewed as a diff before it happens. Nothing is written on toggle.",
    ],
    api: [
      "Prefix is a local preference (shared_preferences), never stored server-side",
      "Policy.AllowedTags on the Jellyfin user must match whatever scheme you pick",
      "POST /Items/{id} replaces the whole item — GET first, mutate Tags, post the full object back",
    ],
  },
  {
    s: "Library — the landing screen",
    b: [
      "Sign-in lands here. The task that brings you into the app is 'find something for a kid', so the app opens on the thing you act on.",
      "The 'Picking for' row uses the same avatars Jellyfin shows the children on their own login screen.",
      "Selecting a child switches the grid to what they can't see yet and turns the rating cap into a one-tap chip.",
      "Already-shared titles are hidden by default and carry a check badge when shown.",
    ],
    api: [
      "GET /Users/{id}/Images/Primary?tag={PrimaryImageTag}",
      "Set difference between the admin's and the child's /Items results gives 'hasn't got yet'",
    ],
  },
  {
    s: "Kids and ratings",
    b: [
      "Allow-list mode (AllowedTags set): the child sees only tagged items — sharing means adding a tag.",
      "Block-list mode (BlockedTags set): sharing means removing one. Every action inverts to match, and the two are never mixed on one account.",
      "Visible counts are fetched twice, once as admin and once as the child, so the server applies the policy rather than the app guessing.",
      "A title above a child's cap can still be selected but is flagged — tagging alone will not make it visible. For a collection the flag reads 'some films are over the limit'.",
    ],
    api: [
      "GET /Users → Policy.AllowedTags, Policy.BlockedTags, Policy.MaxParentalRating",
      "GET /Items?userId={child}&Recursive=true&Limit=0 → TotalRecordCount",
    ],
  },
  {
    s: "Licensing — all GPLv3-safe",
    b: [
      "Fredoka and Nunito are SIL OFL 1.1, which the FSF lists as free and GPL-compatible. Ship OFL.txt beside the .ttf files.",
      "Roboto is Apache 2.0. Avoiding it keeps the bundled font stack entirely OFL — see CLAUDE.md § Licence for why GPLv2 is not a live constraint.",
      "Flutter and Material Components are BSD-3; Material Symbols are Apache 2.0. Both fine inside a GPLv3 app.",
      "The mark is inline vector paths in this file, so it carries your licence and no third-party asset terms.",
      "Jellyfin's name and fin logo stay out of the artwork; the affix in the tagline is what their trademark policy permits.",
    ],
    api: [
      "pubspec.yaml → fonts: family: Fredoka / family: Nunito",
      "Ship LICENSE (GPL-3.0) and assets/fonts/OFL.txt; register both in LicenseRegistry",
    ],
  },
];

function Spec() {
  const [open, setOpen] = useState(0);
  return (
    <div className="m3-spec">
      <h2 className="m3-title-lg m3-spec-title">How it behaves</h2>
      {SPEC.map((s, i) => (
        <div key={s.s} className={open === i ? "m3-acc open" : "m3-acc"}>
          <button className="m3-acc-head" onClick={() => setOpen(open === i ? -1 : i)}>
            <span className="m3-body-large">{s.s}</span>
            <span className="m3-acc-mark">{open === i ? "−" : "+"}</span>
          </button>
          {open === i && (
            <div className="m3-acc-body">
              <ul>{s.b.map((x, j) => <li key={j}>{x}</li>)}</ul>
              <div className="m3-apibox">{s.api.map((a, j) => <code key={j}>{a}</code>)}</div>
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------------- css */

const CSS = `
@import url('https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600&family=Nunito:wght@400;600;700&family=Roboto+Mono:wght@400;500&display=swap');

.m3-root{
  --surface:#141218; --sc-lowest:#0F0D13; --sc-low:#1D1B20; --sc:#211F26;
  --sc-high:#2B2930; --sc-highest:#36343B;
  --on-surface:#E6E0E9; --on-surface-var:#CAC4D0; --outline:#938F99; --outline-var:#49454F;
  --primary:#D0BCFF; --on-primary:#381E72; --primary-container:#4F378B; --on-primary-container:#EADDFF;
  --secondary-container:#4A4458; --on-secondary-container:#E8DEF8;
  --tertiary:#EFB8C8;
  --display:'Fredoka',system-ui,sans-serif;
  font-family:Nunito,system-ui,sans-serif; background:var(--sc-lowest); color:var(--on-surface);
  min-height:100vh; padding:20px 12px 40px; display:flex; flex-direction:column; align-items:center; gap:22px;
}
.m3-root *{box-sizing:border-box}
.m3-root button{font:inherit;color:inherit;background:none;border:none;cursor:pointer;text-align:left}
.m3-root button:focus-visible{outline:3px solid var(--primary);outline-offset:2px}
code{font-family:'Roboto Mono',ui-monospace,monospace}

.m3-display{font-family:var(--display);font-size:40px;font-weight:600;margin:0;line-height:46px;letter-spacing:.4px}
.m3-title-lg{font-family:var(--display);font-size:22px;font-weight:600;margin:0;line-height:28px}
.m3-title{font-family:var(--display);font-size:17px;font-weight:600;line-height:24px}
.m3-body-large{font-size:16px;line-height:24px;font-weight:600}
.m3-body-medium{font-size:14px;line-height:20px;margin:0;font-weight:400}
.m3-label{font-size:12px;line-height:16px;font-weight:600;letter-spacing:.2px}
.m3-value{font-size:14px;color:var(--on-surface-var);flex:none}
.m3-onvar{color:var(--on-surface-var)}
.m3-dim{color:var(--outline);font-weight:400}
.m3-warn{color:var(--tertiary);font-size:12px}
.m3-center{text-align:center}
.m3-overline{font-family:var(--display);margin:18px 0 8px;font-size:12px;font-weight:600;
  letter-spacing:.8px;text-transform:uppercase;color:var(--primary)}
.m3-flush{margin-top:0}
.m3-spacer{height:70px}
.m3-hint{font-size:12px;color:var(--outline)}

.m3-stage{width:100%;max-width:420px;display:flex;flex-direction:column;gap:14px}
.m3-walk{display:flex;flex-direction:column;gap:6px}
.m3-device{background:var(--surface);border-radius:28px;overflow:hidden;display:flex;flex-direction:column;
  height:740px;position:relative;box-shadow:0 24px 60px rgba(0,0,0,.55)}
.m3-statusbar{display:flex;justify-content:space-between;padding:10px 22px 2px;font-size:12px;color:var(--on-surface-var)}
.m3-appbar{display:flex;align-items:center;gap:4px;height:56px;padding:0 12px;flex:none}
.m3-appbar-title{font-family:var(--display);font-size:23px;font-weight:600;line-height:28px;padding-left:4px;flex:1}
.m3-appbar-mark{opacity:.9;display:flex}
.m3-icon-btn{width:40px;height:40px;border-radius:20px;display:grid;place-items:center}
.m3-icon-btn:hover{background:rgba(230,224,233,.08)}
.m3-viewport{flex:1;overflow-y:auto;position:relative;scrollbar-width:thin}
.m3-body{padding:4px 16px 24px;display:flex;flex-direction:column}

.m3-signin{gap:14px;padding-top:24px}
.m3-brand{display:flex;flex-direction:column;align-items:center;gap:2px;margin-bottom:8px}
.m3-textfield{background:var(--sc-high);border-radius:8px 8px 0 0;border-bottom:1px solid var(--outline);
  padding:8px 16px;display:flex;flex-direction:column;gap:2px}
.m3-textfield-label{font-size:12px;color:var(--primary);font-weight:600}
.m3-textfield-value{font-size:16px}
.m3-tabs{display:flex;border-bottom:1px solid var(--outline-var);margin-top:6px}
.m3-tabs button{flex:1;text-align:center;padding:14px 0;font-size:14px;font-weight:700;color:var(--on-surface-var);position:relative}
.m3-tabs button.on{color:var(--primary)}
.m3-tabs button.on::after{content:"";position:absolute;left:20%;right:20%;bottom:0;height:3px;border-radius:3px 3px 0 0;background:var(--primary)}
.m3-code{display:flex;gap:8px}
.m3-code span{flex:1;text-align:center;padding:14px 0;font-family:var(--display);font-weight:600;font-size:24px;
  background:var(--sc-high);border-radius:12px;color:var(--primary)}
.m3-indeterminate{height:4px;border-radius:2px;background:var(--secondary-container);overflow:hidden;position:relative}
.m3-indeterminate i{position:absolute;inset:0;width:36%;border-radius:2px;background:var(--primary);
  animation:m3-slide 1.9s cubic-bezier(.4,0,.2,1) infinite}
@keyframes m3-slide{0%{left:-40%}100%{left:104%}}

.m3-filled{background:var(--primary);color:var(--on-primary);font-family:var(--display);font-size:15px;
  font-weight:600;padding:10px 24px;border-radius:20px;text-align:center;margin-top:10px;min-height:40px}
.m3-filled:disabled{background:rgba(230,224,233,.12);color:rgba(230,224,233,.38);cursor:default}
.m3-text-btn{color:var(--primary);font-size:14px;font-weight:700;padding:10px 12px;border-radius:20px;flex:none}
.m3-text-btn:hover{background:rgba(208,188,255,.08)}
.m3-tight{padding:6px 8px;margin-right:-8px}

.m3-forwhom{padding-top:4px}
.m3-kidrow{display:flex;gap:14px;overflow-x:auto;padding:2px 0 4px;scrollbar-width:none}
.m3-kidrow::-webkit-scrollbar{display:none}
.m3-kidpick{display:flex;flex-direction:column;align-items:center;gap:5px;flex:none;
  color:var(--on-surface-var);width:60px;text-align:center}
.m3-kidpick.on{color:var(--on-surface)}
.m3-kidpick .m3-label{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
.m3-kidpick-all{width:44px;height:44px;border-radius:50%;display:grid;place-items:center;
  background:var(--sc-high);color:var(--on-surface-var)}
.m3-kidpick.on .m3-kidpick-all{background:var(--secondary-container);color:var(--on-secondary-container);
  box-shadow:0 0 0 2px var(--surface),0 0 0 4px var(--primary)}
.m3-avatar{border-radius:50%;display:grid;place-items:center;font-family:var(--display);font-weight:600;flex:none}
.m3-avatar.ring{box-shadow:0 0 0 2px var(--surface),0 0 0 4px var(--ring)}

.m3-filterbar{display:flex;align-items:center;gap:8px;padding:8px 0 2px;
  position:sticky;top:0;background:var(--surface);z-index:5}
.m3-icon-chip{width:36px;height:32px;border-radius:10px;border:1px solid var(--outline);
  display:grid;place-items:center;color:var(--on-surface-var);flex:none}
.m3-chiprow{display:flex;gap:8px;overflow-x:auto;padding:2px 0 6px;scrollbar-width:none;flex:1}
.m3-chiprow::-webkit-scrollbar{display:none}
.m3-chip{display:inline-flex;align-items:center;gap:4px;height:32px;padding:0 8px 0 14px;border-radius:10px;
  border:1px solid var(--outline);color:var(--on-surface-var);font-size:14px;font-weight:700;
  white-space:nowrap;flex:none}
.m3-chip.on{background:var(--secondary-container);color:var(--on-secondary-container);border-color:transparent}
.m3-chip:hover{background:rgba(230,224,233,.08)}
.m3-chip.on:hover{background:var(--secondary-container)}
.m3-resultline{display:flex;align-items:center;justify-content:space-between;padding:6px 0 10px}

.m3-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
.m3-tile{display:flex;flex-direction:column;gap:2px;min-width:0}
.m3-poster-wrap{position:relative}
.m3-stackwrap{position:relative}
.m3-stack-b1,.m3-stack-b2{position:absolute;left:0;right:0;top:0;bottom:0;border-radius:14px;
  background:var(--sc-high);border:1px solid var(--outline-var)}
.m3-stack-b1{transform:translate(4px,-4px)}
.m3-stack-b2{transform:translate(8px,-8px);opacity:.55}
.m3-poster{position:relative;aspect-ratio:2/3;border-radius:14px;overflow:hidden;display:flex;
  flex-direction:column;justify-content:flex-end;padding:8px}
.m3-poster-t{font-family:var(--display);font-size:11.5px;font-weight:600;line-height:1.2;color:rgba(255,255,255,.96)}
.m3-poster-y{font-family:'Roboto Mono',monospace;font-size:9px;color:rgba(255,255,255,.6)}
.m3-badge{position:absolute;top:6px;right:6px;width:22px;height:22px;border-radius:50%;
  background:var(--primary);color:var(--on-primary);display:grid;place-items:center;z-index:2}
.m3-colbadge{position:absolute;left:6px;bottom:6px;display:inline-flex;align-items:center;gap:3px;
  height:18px;padding:0 6px;border-radius:9px;background:rgba(20,18,24,.82);color:var(--primary);
  font-size:10px;font-weight:700;z-index:2}
.m3-tile-t{margin-top:4px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-weight:600}
.m3-tile-dots{display:flex;gap:4px;align-items:center;min-height:22px;margin-top:4px}

.m3-card{background:var(--sc-low);border-radius:16px;padding:16px;margin-bottom:8px;display:flex;
  flex-direction:column;gap:10px;width:100%}
.m3-card:hover{background:var(--sc)}
.m3-card-top{display:flex;align-items:center;gap:16px}
.m3-card-headline{flex:1;display:flex;flex-direction:column;min-width:0}
.m3-list-item{display:flex;align-items:center;gap:16px;padding:12px 0;min-height:64px}
.m3-list-text{flex:1;display:flex;flex-direction:column;min-width:0}
.m3-assist{display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 10px;border-radius:10px;
  font-size:12px;font-weight:700;flex:none}
.m3-assist-ok{background:var(--secondary-container);color:var(--on-secondary-container)}
.m3-assist-warn{background:#4D3A2E;color:#F5D3B8}
.m3-tagwrap{display:flex;flex-wrap:wrap;gap:6px}
.m3-code-chip{font-size:12px;background:var(--sc-highest);color:var(--on-surface-var);padding:3px 8px;border-radius:8px}
.m3-code-chip.add{background:#28402F;color:#A8D8B9}
.m3-code-chip.rm{background:#4D3A2E;color:#F5D3B8}
.m3-progress{position:relative;height:5px;border-radius:3px;overflow:hidden}
.m3-progress-track{position:absolute;inset:0;background:var(--secondary-container);border-radius:3px}
.m3-progress-bar{position:absolute;left:0;top:0;bottom:0;border-radius:3px;transition:width .45s cubic-bezier(.2,0,0,1)}

.m3-hero{border-radius:20px;padding:20px;display:flex;flex-direction:column;gap:6px;margin-top:8px}
.m3-hero-num{font-family:var(--display);font-size:44px;font-weight:600;line-height:50px;margin-top:8px}
.m3-hero-note{color:var(--on-surface-var);margin-top:8px}
.m3-lib{padding:14px 0;border-bottom:1px solid var(--outline-var);display:flex;flex-direction:column;gap:8px}
.m3-lib-row{display:flex;justify-content:space-between;align-items:center}
.m3-lib.off{opacity:.38}

.m3-setting{display:flex;align-items:center;gap:16px;padding:12px 0;min-height:64px;width:100%}
.m3-setting:hover{background:rgba(230,224,233,.04)}
.m3-setting.dim{opacity:.45}
.m3-about{display:flex;align-items:center;gap:14px;background:var(--sc-low);border-radius:16px;padding:14px}
.m3-switch{width:52px;height:32px;border-radius:16px;background:var(--sc-highest);
  border:2px solid var(--outline);position:relative;flex:none;transition:background .2s,border-color .2s}
.m3-switch.on{background:var(--primary);border-color:var(--primary)}
.m3-switch-thumb{position:absolute;left:4px;top:50%;width:16px;height:16px;border-radius:50%;
  background:var(--outline);display:grid;place-items:center;color:var(--on-primary);
  transform:translateY(-50%);transition:left .2s cubic-bezier(.2,0,0,1),width .2s,height .2s,background .2s}
.m3-switch.on .m3-switch-thumb{left:26px;width:24px;height:24px;background:var(--on-primary)}

.m3-fab{position:absolute;right:16px;bottom:16px;display:inline-flex;align-items:center;gap:8px;
  height:56px;padding:0 20px;border-radius:18px;background:var(--primary-container);
  color:var(--on-primary-container);font-family:var(--display);font-size:15px;font-weight:600;
  box-shadow:0 3px 8px rgba(0,0,0,.4);z-index:10}

.m3-scrim{position:absolute;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:flex-end;z-index:20;
  animation:m3-fade .15s linear}
.m3-scrim.center{align-items:center;justify-content:center;padding:24px}
@keyframes m3-fade{from{opacity:0}to{opacity:1}}
.m3-sheet{width:100%;max-height:88%;overflow-y:auto;background:var(--sc-low);border-radius:28px 28px 0 0;
  padding:0 16px 20px;display:flex;flex-direction:column;animation:m3-up .28s cubic-bezier(.05,.7,.1,1)}
@keyframes m3-up{from{transform:translateY(100%)}to{transform:translateY(0)}}
.m3-handle{width:32px;height:4px;border-radius:2px;background:var(--on-surface-var);opacity:.4;margin:12px auto 8px}
.m3-sheet-head{display:flex;gap:16px;align-items:flex-end;padding:4px 0 8px}
.m3-sheet-poster{width:72px;flex:none}
.m3-note{display:flex;align-items:flex-start;gap:10px;background:var(--secondary-container);
  color:var(--on-secondary-container);border-radius:14px;padding:12px 14px;margin-top:4px}
.m3-note.soft{background:var(--sc-high);color:var(--on-surface-var)}
.m3-note svg{flex:none;margin-top:1px}
.m3-menugroup{display:flex;flex-direction:column}
.m3-menuitem{display:flex;align-items:center;gap:14px;min-height:48px;padding:0 4px;border-radius:10px}
.m3-menuitem:hover{background:rgba(230,224,233,.06)}
.m3-radio{width:18px;height:18px;border-radius:50%;border:2px solid var(--on-surface-var);flex:none}
.m3-radio.on{border-color:var(--primary);box-shadow:inset 0 0 0 3px var(--sc-low),inset 0 0 0 9px var(--primary)}
.m3-select{display:flex;align-items:center;gap:16px;padding:12px;border-radius:16px;min-height:64px;
  background:var(--sc);margin-bottom:8px}
.m3-select.on{background:var(--secondary-container)}
.m3-checkbox{width:18px;height:18px;border-radius:4px;border:2px solid var(--on-surface-var);
  display:grid;place-items:center;flex:none;color:var(--on-primary)}
.m3-checkbox.on{background:var(--primary);border-color:var(--primary)}
.m3-diff{background:var(--sc-highest);border-radius:16px;padding:14px;display:flex;flex-direction:column;gap:8px;margin-top:6px}
.m3-sheet-actions{display:flex;justify-content:flex-end;align-items:center;gap:8px;margin-top:14px}
.m3-sheet-actions .m3-filled{margin-top:0}

/* dialog */
.m3-dialog{background:var(--sc-high);border-radius:28px;padding:24px;width:100%;max-width:320px;
  display:flex;flex-direction:column;gap:12px;align-items:center;
  animation:m3-pop .2s cubic-bezier(.05,.7,.1,1);max-height:90%;overflow-y:auto}
@keyframes m3-pop{from{transform:scale(.9);opacity:0}to{transform:scale(1);opacity:1}}
.m3-dialog-icon{color:var(--primary)}
.m3-dialog-list{width:100%;display:flex;flex-direction:column;gap:4px;background:var(--sc-lowest);
  border-radius:14px;padding:10px 12px;margin-top:2px}
.m3-dialog-row{display:flex;align-items:center;justify-content:space-between;gap:10px}
.m3-dialog-actions{display:flex;justify-content:flex-end;align-items:center;gap:8px;width:100%;margin-top:6px}
.m3-dialog-actions .m3-filled{margin-top:0}

.m3-snackbar{position:absolute;left:16px;right:16px;bottom:16px;background:#E6E0E9;color:#322F35;
  border-radius:8px;padding:14px 8px 14px 16px;font-size:14px;font-weight:600;display:flex;align-items:center;
  gap:8px;box-shadow:0 3px 8px rgba(0,0,0,.45);z-index:30;animation:m3-up .2s ease}
.m3-snackbar span{flex:1}
.m3-snack-action{color:#6750A4;font-weight:700;font-size:14px;padding:8px 12px;border-radius:20px;flex:none}

.m3-navbar{display:flex;height:80px;background:var(--sc);padding-top:12px;align-items:flex-start;flex:none}
.m3-navitem{flex:1;display:flex;flex-direction:column;align-items:center;gap:4px;color:var(--on-surface-var)}
.m3-nav-pill{width:60px;height:32px;border-radius:16px;display:grid;place-items:center;transition:background .15s}
.m3-navitem.on{color:var(--on-secondary-container)}
.m3-navitem.on .m3-nav-pill{background:var(--secondary-container)}
.m3-nav-label{font-size:12px;font-weight:700}
.m3-navitem.on .m3-nav-label{color:var(--on-surface)}

.m3-spec{width:100%;max-width:420px;display:flex;flex-direction:column;gap:8px}
.m3-spec-title{margin-bottom:4px}
.m3-acc{background:var(--sc-low);border-radius:16px;overflow:hidden}
.m3-acc-head{display:flex;justify-content:space-between;align-items:center;width:100%;padding:16px;min-height:56px}
.m3-acc-mark{color:var(--on-surface-var);font-size:18px}
.m3-acc-body{padding:0 16px 16px;display:flex;flex-direction:column;gap:12px}
.m3-acc-body ul{margin:0;padding-left:20px;display:flex;flex-direction:column;gap:8px}
.m3-acc-body li{font-size:14px;line-height:20px;color:var(--on-surface-var)}
.m3-apibox{background:var(--sc-lowest);border-radius:10px;padding:12px;display:flex;flex-direction:column;gap:5px}
.m3-apibox code{font-size:11px;line-height:1.5;color:var(--outline);word-break:break-all}

@media (prefers-reduced-motion:reduce){.m3-root *{animation:none!important;transition:none!important}}
@media (max-width:400px){.m3-grid{grid-template-columns:repeat(2,1fr)}.m3-device{height:680px}}
`;
