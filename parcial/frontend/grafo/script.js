document.addEventListener('DOMContentLoaded', () => {
  const zones = document.querySelectorAll('.zone');

  zones.forEach((zone) => {
    zone.setAttribute('tabindex', '0');
    zone.setAttribute('role', 'button');

    const selectZone = () => {
      zones.forEach((item) => item.classList.remove('is-selected'));
      zone.classList.add('is-selected');
    };

    zone.addEventListener('click', selectZone);
    zone.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        selectZone();
      }
    });
  });
});
