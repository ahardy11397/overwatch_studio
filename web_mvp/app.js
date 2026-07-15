// Audio Fader Logic
const fader = document.getElementById('fader1');
const meter = document.getElementById('meter1');

let isDragging = false;
let startY, startBottom;

fader.addEventListener('mousedown', (e) => {
    isDragging = true;
    startY = e.clientY;
    startBottom = parseFloat(getComputedStyle(fader).bottom);
    fader.style.cursor = 'grabbing';
});

window.addEventListener('mousemove', (e) => {
    if (!isDragging) return;
    const dy = startY - e.clientY;
    let newBottom = startBottom + dy;
    // Track is 250px, cap is 18px. Range ~ 0 to 232
    if (newBottom < 0) newBottom = 0;
    if (newBottom > 232) newBottom = 232;
    
    fader.style.bottom = newBottom + 'px';
    
    // Simulate audio meter based on fader position
    const volumePercent = newBottom / 232;
    // Add some random flutter
    const flutter = Math.random() * 0.1;
    meter.style.height = ((volumePercent * 0.8 + flutter) * 100) + '%';
});

window.addEventListener('mouseup', () => {
    isDragging = false;
    fader.style.cursor = 'pointer';
});

// Video Switcher Logic
const cutBtn = document.querySelector('.cut-btn');
const programFeed = document.querySelector('.program');
const previewFeed = document.querySelector('.preview');

let isCam1Live = false;

cutBtn.addEventListener('click', () => {
    isCam1Live = !isCam1Live;
    if (isCam1Live) {
        programFeed.textContent = "Program (Cam 1)";
        previewFeed.textContent = "Preview (Cam 2)";
    } else {
        programFeed.textContent = "Program (Cam 2)";
        previewFeed.textContent = "Preview (Cam 1)";
    }
});

// Show Builder Logic
const cues = document.querySelectorAll('.cue-item');
cues.forEach(cue => {
    cue.addEventListener('click', () => {
        cues.forEach(c => c.classList.remove('active-cue'));
        cue.classList.add('active-cue');
    });
});
