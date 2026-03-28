const fs = require('fs');
const appPath = 'c:\\Users\\PC_User\\Desktop\\EA-Labo\\app.js';
let app = fs.readFileSync(appPath, 'utf8');

// 1. Fix setupStep0 to progress from Template select to Step 1
// Matching id !== null) { ... }
const setupRegex = /if \(id !== null\) \{[\s\S]*?applyTemplate\(parseInt\(id\)\);[\s\S]*?\}/;
const newSetup = `if (id !== null) {
                applyTemplate(parseInt(id));
                showEAStep(1);
            }`;
app = app.replace(setupRegex, newSetup);

// 2. Fix showEAStep to handle Home Screen and Dashboard and 1-8 loop
const showEARegex = /function showEAStep\(stepNum\) \{[\s\S]*?\n\}/;
const newShowEA = `function showEAStep(stepNum) {
    if (typeof closeWizard === 'function') closeWizard();
    
    // ホーム画面とベースのフローコンテナの表示制御
    const home = document.getElementById('home-screen');
    const flow = document.getElementById('ea-flow');
    if (home) home.classList.add('hidden');
    if (flow) flow.classList.remove('hidden');

    // 全ステップ（0-8）を確実に隠す
    for (let i = 0; i <= 8; i++) { 
        const s = document.getElementById(\`ea-step-\${i}\`); 
        if (s) {
            s.classList.add('hidden');
            s.style.display = 'none'; 
        }
    }
    // 対象ステップを表示
    const target = document.getElementById(\`ea-step-\${stepNum}\`); 
    if (target) {
        target.classList.remove('hidden');
        target.style.display = 'block';
    }
    updateEAProgress(stepNum);
    window.scrollTo(0, 0); 
}`;
app = app.replace(showEARegex, newShowEA);

fs.writeFileSync(appPath, app, 'utf8');
console.log("app.js fixed (Step 0 progression and UI overlap).");
