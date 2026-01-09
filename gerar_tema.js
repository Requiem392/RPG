const fs = require('fs');
const path = require('path');

// === CONFIGURAÇÕES ===
const iconsDir = path.join(__dirname, 'icons');
// ATENÇÃO: Verifique se este caminho está apontando para a pasta da sua extensão instalada corretamente
// Se estiver rodando local, use o caminho relativo
const outputFile = path.join(__dirname, 'theme.json');

const gameFolder = path.join(__dirname, 'Game'); // Pasta exportada pelo Lune

// === ESTRUTURA BASE ===
const theme = {
    "iconDefinitions": {
        "_default": { "iconPath": "./icons/Part.png" },
        "_folder": { "iconPath": "./icons/Folder.png" },
        "_folder_open": { "iconPath": "./icons/Folder.png" }
    },
    "fileExtensions": { "rbxm": "_default", "rbxmx": "_default" },
    "folderNames": {},
    "folderNamesExpanded": {},
    "folder": "_folder",
    "folderExpanded": "_folder_open"
};

// 1. CARREGAR ÍCONES
if (!fs.existsSync(iconsDir)) {
    console.error("❌ Pasta 'icons' não encontrada!");
    process.exit(1);
}

const files = fs.readdirSync(iconsDir);
const iconMap = {}; // Mapa: 'workspace' -> '_workspace'

files.forEach(file => {
    if (file.startsWith('.')) return;
    const nameOriginal = path.parse(file).name;
    const nameLower = nameOriginal.toLowerCase();
    const id = `_${nameLower}`;

    theme.iconDefinitions[id] = { "iconPath": `./icons/${file}` };
    iconMap[nameLower] = id; // Guarda referência: "replicatedstorage" usa o ID "_replicatedstorage"

    // Regras de Arquivos
    theme.fileExtensions[`${nameLower}.rbxmx`] = id;
    theme.fileExtensions[`${nameLower}.rbxm`] = id;

    // Regras de Scripts
    if (nameLower === 'localscript') theme.fileExtensions['client.luau'] = id;
    if (nameLower === 'script') theme.fileExtensions['server.luau'] = id;
    if (nameLower === 'modulescript') theme.fileExtensions['module.luau'] = id;
});

// 2. ESCANEAMENTO INTELIGENTE DAS PASTAS
function scanFolder(dir) {
    if (!fs.existsSync(dir)) return;

    const items = fs.readdirSync(dir, { withFileTypes: true });

    items.forEach(item => {
        if (item.isDirectory()) {
            const folderName = item.name;
            const folderNameLower = folderName.toLowerCase();

            // CASO 1: Pasta com sufixo (ex: "CombateUI.screengui")
            // Pega o que tem depois do último ponto
            const parts = folderName.split('.');
            if (parts.length > 1) {
                const suffix = parts[parts.length - 1].toLowerCase();
                if (iconMap[suffix]) {
                    const id = iconMap[suffix];
                    theme.folderNames[folderName] = id;
                    theme.folderNamesExpanded[folderName] = id;
                }
            }

            // CASO 2: Pasta com nome exato de um ícone (ex: "Workspace", "ReplicatedStorage")
            // AQUI QUE CONSERTAMOS OS SERVIÇOS!
            if (iconMap[folderNameLower]) {
                const id = iconMap[folderNameLower];
                theme.folderNames[folderName] = id;
                theme.folderNamesExpanded[folderName] = id;
                console.log(`🔹 Serviço Detectado: ${folderName} -> Ícone: ${id}`);
            }

            // Recursão
            scanFolder(path.join(dir, folderName));
        }
    });
}

console.log(`🕵️ Lendo estrutura em: ${gameFolder}`);
scanFolder(gameFolder);

// 3. SALVAR
fs.writeFileSync(outputFile, JSON.stringify(theme, null, 2));
console.log(`✅ theme.json atualizado! Copie para a pasta da extensão e recarregue.`);