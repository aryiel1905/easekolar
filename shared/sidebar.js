// Shared Admin Sidebar Loader
(function(){
  async function loadAdminSidebar(activeKey){
    const root = document.getElementById('sidebar-root');
    if (!root) return;
    try {
      const res = await fetch('shared/sidebar.html', { cache: 'no-cache' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const html = await res.text();
      root.innerHTML = html;
      // highlight active
      const active = root.querySelector(`a[data-active="${activeKey}"]`);
      if (active) active.classList.add('active');
      // logout wiring (clear admin context)
      const btn = root.querySelector('#logout-btn');
      if (btn) btn.addEventListener('click', () => {
        try {
          localStorage.removeItem('adminCampus');
          localStorage.removeItem('adminRole');
          localStorage.removeItem('adminName');
        } catch(_) {}
        window.location.href = 'login-signup.html';
      });

      // populate profile
      const name = (localStorage.getItem('adminName') || 'Admin').trim();
      const roleRaw = (localStorage.getItem('adminRole') || '').trim();
      const role = roleRaw
        ? (roleRaw === 'main_admin' ? 'Main Admin' : roleRaw === 'program_admin' ? 'Program Admin' : roleRaw)
        : 'Logged in';
      const nameEl = root.querySelector('#sidebarAdminName');
      const roleEl = root.querySelector('#sidebarAdminRole');
      if (nameEl) nameEl.textContent = name;
      if (roleEl) roleEl.textContent = role;
    } catch (e) {
      console.warn('Failed to load sidebar:', e);
    }
  }
  window.loadAdminSidebar = loadAdminSidebar;
})();
