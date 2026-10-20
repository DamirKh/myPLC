(function () {
   var KEY = 'thermostat.theme';
   var root = document.documentElement;
   var media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

   function stored() {
      try {
         var value = localStorage.getItem(KEY);
         return value === 'light' || value === 'dark' ? value : null;
      } catch (e) {
         return null;
      }
   }

   function preferred() {
      return stored() || (media && media.matches ? 'dark' : 'light');
   }

   function current() {
      return root.dataset.theme === 'dark' ? 'dark' : 'light';
   }

   function apply(theme, persist) {
      theme = theme === 'dark' ? 'dark' : 'light';
      root.dataset.theme = theme;
      if (persist) {
         try { localStorage.setItem(KEY, theme); } catch (e) {}
      }
      document.dispatchEvent(new CustomEvent('thermostat:theme', {detail: {theme: theme}}));
   }

   apply(preferred(), false);

   window.thermostatTheme = {
      current: current,
      toggle: function () {
         var next = current() === 'dark' ? 'light' : 'dark';
         apply(next, true);
         return next;
      }
   };

   if (media && media.addEventListener) {
      media.addEventListener('change', function () {
         if (!stored()) apply(media.matches ? 'dark' : 'light', false);
      });
   }
})();
