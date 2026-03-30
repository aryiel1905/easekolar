// Shared Admin Sidebar Loader
(function(){
  const STYLE_ID = 'adminSidebarStudentStyle';
  const SIDEBAR_TEMPLATE_URL = 'shared/sidebar.html?v=20260331a';

  function ensureProfileBlock(root){
    const card = root.querySelector('.admin-profile-card');
    if (!card) return;

    const hasName = !!card.querySelector('#sidebarAdminName');
    const hasRole = !!card.querySelector('#sidebarAdminRole');
    const hasLogout = !!card.querySelector('#adminSidebarLogoutBtn');
    if (hasName && hasRole && hasLogout) return;

    card.innerHTML = `
      <div class="admin-profile-row">
        <div class="admin-avatar" aria-hidden="true">
          <svg viewBox="0 0 24 24" fill="none">
            <circle cx="12" cy="8" r="4" stroke="currentColor" stroke-width="1.8"></circle>
            <path d="M4.5 19.5c1.5-3 4-4.5 7.5-4.5s6 1.5 7.5 4.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"></path>
          </svg>
        </div>
        <div class="admin-profile-meta" id="sidebarAdminMeta">
          <div id="sidebarAdminName" class="admin-profile-name">Admin</div>
          <div id="sidebarAdminRole" class="admin-profile-role">Logged in</div>
        </div>
      </div>
      <button id="adminSidebarLogoutBtn" class="admin-logout-btn">
        <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <path d="M14 7l5 5-5 5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"></path>
          <path d="M19 12H9" stroke="currentColor" stroke-width="2" stroke-linecap="round"></path>
          <path d="M5 5h4v14H5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"></path>
        </svg>
        <span id="logoutLabel">Logout</span>
      </button>
    `;
  }

  function ensureSidebarStyles(){
    if (document.getElementById(STYLE_ID)) return;

    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
#sidebar-root{ width:280px; border-right:1px solid var(--line, var(--sidebar-border, #d5deec)); }
#sidebar-root .admin-sidebar{ background:var(--sidebar, #c6cfdb); padding:22px 16px; height:100%; display:grid; grid-template-rows:auto 1fr auto; gap:24px; }
#sidebar-root .admin-mode-toggle{ display:flex; align-items:center; gap:12px; padding:10px 12px; border-radius:16px; width:100%; border:1px solid var(--line, var(--sidebar-border, #d5deec)); background:var(--card, var(--panel, #ffffff)); box-shadow:0 10px 28px rgba(24,37,56,.08); cursor:pointer; text-align:left; }
#sidebar-root .admin-mode-toggle strong{ letter-spacing:.2px; color:var(--ink, var(--text, #0f274b)); }
#sidebar-root .admin-mode-toggle small{ display:block; color:#5f6f8a; font-weight:700; }
#sidebar-root .admin-mode-icon{ width:36px; height:36px; border-radius:12px; display:grid; place-items:center; background:linear-gradient(135deg,#6EA8FF 0%,#7E85FF 50%,#B06BFF 100%); color:#fff; font-size:18px; }
#sidebar-root .admin-mode-icon svg{ width:20px; height:20px; display:block; }
#sidebar-root .admin-menu h5{ font-size:12px; color:#7D8AA3; letter-spacing:.4px; margin:6px 10px; text-transform:uppercase; font-weight:800; }
#sidebar-root .admin-menu{ display:grid; gap:6px; align-content:start; }
#sidebar-root .admin-menu a{ display:flex; align-items:center; gap:12px; padding:12px 12px; border-radius:12px; text-decoration:none; color:#3B4A5E; font-weight:700; }
#sidebar-root .admin-menu a:hover,
#sidebar-root .admin-menu a.active{ background:color-mix(in oklab, var(--primary-100, #eaf1ff) 60%, white 0%); color:var(--primary, #1c3d77); box-shadow:inset 0 0 0 1px color-mix(in oklab, var(--primary, #1c3d77) 22%, var(--line, #d5deec)); }
#sidebar-root .admin-sidebar-bottom{ margin-top:auto; }
#sidebar-root .admin-profile-card{ border:1px solid var(--line, var(--sidebar-border, #d5deec)); border-radius:16px; background:var(--card, var(--panel, #ffffff)); padding:12px; min-height:132px; display:flex; flex-direction:column; justify-content:flex-start; }
#sidebar-root .admin-profile-row{ display:flex; align-items:center; gap:10px; margin-bottom:10px; }
#sidebar-root .admin-avatar{ width:40px; height:40px; border-radius:12px; background:#EEF2FF; display:grid; place-items:center; font-weight:800; }
#sidebar-root .admin-avatar svg{ width:20px; height:20px; display:block; color:#1F2A37; }
#sidebar-root .admin-profile-meta{ display:block !important; flex:1; min-width:0; }
#sidebar-root .admin-profile-name{ font-weight:800; color:var(--ink, var(--text, #0f274b)); }
#sidebar-root .admin-profile-role{ color:#5f6f8a; font-size:12px; }
#sidebar-root .admin-profile-name,
#sidebar-root .admin-profile-role{ display:block !important; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; line-height:1.25; }
#sidebar-root .admin-logout-btn{ margin-top:10px; width:100%; padding:10px 12px; border:none; border-radius:12px; cursor:pointer; background:#F1F5FF; color:#243B77; font-weight:800; display:flex !important; align-items:center; justify-content:center; gap:8px; }
#sidebar-root .admin-logout-btn svg{ width:16px; height:16px; display:block; }
#sidebar-root .admin-logout-btn span{ display:inline !important; }
#sidebar-root .admin-profile-meta *{ display:block !important; visibility:visible !important; opacity:1 !important; }
[data-theme='dark'] #sidebar-root .admin-mode-toggle{ background:#0F1C3C; border-color:#1C2C56; }
[data-theme='dark'] #sidebar-root .admin-mode-toggle strong{ color:#E7EEFF; }
[data-theme='dark'] #sidebar-root .admin-mode-toggle small{ color:#9FB3D6; }
[data-theme='dark'] #sidebar-root .admin-menu h5{ color:#8FA3C7; }
[data-theme='dark'] #sidebar-root .admin-menu a{ color:#BFD0EE; }
[data-theme='dark'] #sidebar-root .admin-menu a:hover,
[data-theme='dark'] #sidebar-root .admin-menu a.active{ background:#172B59; color:#9DB7FF; box-shadow:inset 0 0 0 1px #203055; }
[data-theme='dark'] #sidebar-root .admin-profile-card{ background:#0F1C3C; border-color:#1C2C56; }
[data-theme='dark'] #sidebar-root .admin-avatar{ background:#19274B; color:#C7D7FF; }
[data-theme='dark'] #sidebar-root .admin-avatar svg{ color:#C7D7FF; }
[data-theme='dark'] #sidebar-root .admin-profile-name{ color:#E7EEFF; }
[data-theme='dark'] #sidebar-root .admin-profile-role{ color:#9FB3D6; }
[data-theme='dark'] #sidebar-root .admin-logout-btn{ background:#1A2850; color:#C7D7FF; }
`;

    document.head.appendChild(style);
  }

  function getInitialTheme(){
    const saved = localStorage.getItem('theme');
    if (saved === 'dark' || saved === 'light') return saved;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function setTheme(theme){
    const next = theme === 'dark' ? 'dark' : 'light';
    document.documentElement.setAttribute('data-theme', next);
    try {
      localStorage.setItem('theme', next);
      localStorage.setItem('scholarship_theme', next);
    } catch (_) {}
    updateThemeUI();
  }

  function updateThemeUI(){
    const toggle = document.getElementById('adminModeToggle');
    const icon = document.getElementById('adminModeIcon');
    const label = document.getElementById('adminModeLabel');
    const legacyToggle = document.getElementById('theme-toggle');
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    if (toggle) toggle.setAttribute('aria-pressed', String(isDark));
    if (icon) {
      icon.innerHTML = isDark
        ? '<svg viewBox="0 0 24 24" fill="none"><path d="M20 14.5A8.5 8.5 0 1 1 9.5 4 7 7 0 0 0 20 14.5Z" fill="#E7EEFF" stroke="#C7D7FF" stroke-width="1.5"/></svg>'
        : '<svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="5" fill="#FACC15" stroke="#111827" stroke-width="1.5"/><path d="M12 2v2M12 20v2M4.93 4.93l1.42 1.42M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.42-1.42M17.66 6.34l1.41-1.41" stroke="#111827" stroke-width="1.5" stroke-linecap="round"/></svg>';
    }
    if (label) label.textContent = isDark ? 'Dark mode' : 'Light mode';
    if (legacyToggle) legacyToggle.textContent = isDark ? 'Light' : 'Dark';
  }

  function toggleTheme(){
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    setTheme(isDark ? 'light' : 'dark');
  }

  async function loadAdminSidebar(activeKey){
    const root = document.getElementById('sidebar-root');
    if (!root) return;

    ensureSidebarStyles();
    setTheme(getInitialTheme());

    try {
      const res = await fetch(SIDEBAR_TEMPLATE_URL, { cache: 'no-cache' });
      if (!res.ok) throw new Error('HTTP ' + res.status);

      const html = await res.text();
      root.innerHTML = html;
      ensureProfileBlock(root);

      const active = root.querySelector(`a[data-active="${activeKey}"]`);
      if (active) active.classList.add('active');

      const modeBtn = root.querySelector('#adminModeToggle');
      if (modeBtn) modeBtn.addEventListener('click', toggleTheme);

      const legacyToggle = document.getElementById('theme-toggle');
      if (legacyToggle && !legacyToggle.dataset.boundTheme) {
        legacyToggle.addEventListener('click', toggleTheme);
        legacyToggle.dataset.boundTheme = '1';
      }

      const btn = root.querySelector('#adminSidebarLogoutBtn');
      if (btn) {
        // Fail-safe visibility in case page-level CSS hides sidebar controls.
        btn.style.display = 'flex';
        btn.style.visibility = 'visible';
        btn.style.opacity = '1';
        btn.addEventListener('click', () => {
          try {
            localStorage.removeItem('adminCampus');
            localStorage.removeItem('adminRole');
            localStorage.removeItem('adminName');
          } catch (_) {}
          window.location.href = 'login-signup.html';
        });
      }

      const rawName = (localStorage.getItem('adminName') || '').trim();
      const name = rawName || 'Admin';
      const roleRaw = (localStorage.getItem('adminRole') || '').trim();
      const role = roleRaw
        ? (roleRaw === 'main_admin' ? 'Main Admin' : roleRaw === 'program_admin' ? 'Program Admin' : roleRaw)
        : 'Logged in';

      const nameEl = root.querySelector('#sidebarAdminName');
      const roleEl = root.querySelector('#sidebarAdminRole');
      const logoutLabelEl = root.querySelector('#logoutLabel');
      if (nameEl) {
        nameEl.textContent = name;
        nameEl.style.display = 'block';
        nameEl.style.visibility = 'visible';
        nameEl.style.opacity = '1';
      }
      if (roleEl) {
        roleEl.textContent = role;
        roleEl.style.display = 'block';
        roleEl.style.visibility = 'visible';
        roleEl.style.opacity = '1';
      }

      const profileMeta = root.querySelector('.admin-profile-meta');
      if (profileMeta) {
        profileMeta.style.display = 'block';
        profileMeta.style.visibility = 'visible';
        profileMeta.style.opacity = '1';
      }
      if (logoutLabelEl) {
        logoutLabelEl.textContent = 'Logout';
        logoutLabelEl.style.display = 'inline';
        logoutLabelEl.style.visibility = 'visible';
        logoutLabelEl.style.opacity = '1';
      }

      updateThemeUI();
    } catch (e) {
      console.warn('Failed to load sidebar:', e);
    }
  }

  window.loadAdminSidebar = loadAdminSidebar;
  window.setAdminTheme = setTheme;
  window.toggleAdminTheme = toggleTheme;
})();
