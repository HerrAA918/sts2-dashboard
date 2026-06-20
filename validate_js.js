const fs = require('fs');
const vm = require('vm');
const path = require('path');

try {
    const html = fs.readFileSync(path.join(__dirname, "sts2_dashboard.html"), 'utf8');
    
    // Regex to find all <script> blocks
    const scriptRegex = /<script>([\s\S]*?)<\/script>/gi;
    let match;
    let count = 0;
    
    while ((match = scriptRegex.exec(html)) !== null) {
        const jsCode = match[1];
        count++;
        
        // Skip script tags that just define variables with templated placeholders if any
        if (jsCode.includes('__RUN_DATA__') || jsCode.includes('__DB_DATA__')) {
            console.log(`Script block ${count}: Skipping template data block`);
            continue;
        }
        
        try {
            new vm.Script(jsCode);
            console.log(`Script block ${count}: Compiled successfully (size: ${jsCode.length} chars)`);
        } catch (err) {
            console.error(`Script block ${count} compilation FAILED:`, err);
            process.exit(1);
        }
    }
    
    console.log("All script blocks validated successfully!");
} catch (err) {
    console.error("Error reading or parsing file:", err);
    process.exit(1);
}
