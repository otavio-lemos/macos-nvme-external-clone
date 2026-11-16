# Utilizando um NVMe externo em dois macOS

Guia técnico e scripts para clonar o macOS (testado no **macOS 27.2.1 / Build 26B131**) de um Mac Apple Silicon para um **SSD NVMe externo**:

- **SSD interno de ambos os Macs intacto** (boot independente no NVMe externo)
- **System Integrity Protection (`SIP`) ativado** (`csrutil status: enabled`)
- **Siri AI / Apple Intelligence** funcionando em todos os cenários
- **Espelhamento do iPhone (`iPhone Mirroring`)** funcionando em todos os cenários

---

## Hardware e Cenário de Uso

- **Origem do clone:** MacBook Pro M3 Pro (18 GB RAM)
- **Segundo Mac:** MacBook Pro M4 Pro (48 GB RAM)
- **Case externo:** ACASIS TBU405 Air (Thunderbolt / USB4 40 Gb/s)
- **SSD NVMe:** Hiksemi Future Lite 1 TB (`HS-SSD-FUTURE Lite 1024G`)
- **Uso:** O mesmo NVMe externo fica horas em um macOS e horas no outro.

---

## Arquivos do Repositório

| Arquivo | Função | Onde executar |
|---|---|---|
| [`README.md`](./README.md) | Documentação completa do clone, política de boot (`LocalPolicy`/`Preboot`), Siri AI e Espelhamento do iPhone | Referência |
| [`fix_siri.sh`](./fix_siri.sh) | Script POSIX `/bin/sh` (usa `PlistBuddy` + `chflags`) que libera e trava a elegibilidade da Siri AI / Apple Intelligence | Terminal do **Modo Recovery** |
| [`fix_iphone_mirroring.sh`](./fix_iphone_mirroring.sh) | Limpa o cache preso do `replicatord` / `ScreenContinuity` após clonar ou alternar entre Macs | Terminal do **macOS normal** |
| [`fix_siri.py`](./fix_siri.py) | Versão inicial em Python (funciona apenas com boot normal + SIP desativado; **não** funciona no Recovery porque não há `python3` no `arm64eBaseSystem.dmg`) | Apenas referência histórica |

---

## Etapa 1 — Clonagem do macOS para o NVMe Externo

### 1.1 Por que `dd` no Modo Recovery foi descartado
Na tentativa inicial via Terminal no Modo Recovery:
- `dd if=/dev/diskX of=/dev/diskY` ficou extremamente lento pelo buffer padrão de bloco.
- Alterar para dispositivos *raw* (`dd if=/dev/rdiskX of=/dev/rdiskY`) também não trouxe ganho prático suficiente para um SSD grande e foi interrompido.
- Além de copiar setor a setor todo o espaço vazio do SSD, o `dd` copia UUIDs idênticos de container/volume APFS e **não** gera a assinatura de boot do **Secure Enclave** na máquina de destino.

### 1.2 Método definitivo: Utilitário de Disco (`Disk Utility`) com o macOS montado
Com o macOS de origem inicializado normalmente:

1. Abra o **Utilitário de Disco** (`Disk Utility`) e ative **Visualizar > Mostrar Todos os Dispositivos** (`Cmd + 2`).
2. Selecione a **raiz física** do NVMe externo (ex.: `/dev/disk4`, o dispositivo acima do container/volumes) e clique em **Apagar** (`Erase`):
   - **Nome:** `Macintosh HD`
   - **Formato:** `APFS`
   - **Esquema:** `Mapa de Partição GUID` (`GUID Partition Map`)
3. Selecione o novo volume APFS criado no NVMe externo, clique em **Restaurar** (`Restore`) e escolha em **Restaurar de:** o volume de dados de origem (**`Data`** ou **`Macintosh HD - Data`**).
4. Aguarde a conclusão. O Utilitário de Disco usa a replicação APFS nativa (`asr`), copiando apenas os blocos em uso e recriando o **APFS Volume Group** completo (Sistema selado + Dados + `Preboot` + `Recovery` + `VM`).

### 1.3 Equivalente via Terminal (`diskutil` + `asr`)
Caso prefira fazer a formatação e a restauração APFS diretamente pelo Terminal (ajuste `/dev/diskX` e `<volume_origem>` usando `diskutil list`):

```sh
# 1. Identifique o disco externo e o volume de origem
diskutil list

# 2. Formate a raiz física do NVMe externo em GPT + APFS
diskutil eraseDisk APFS "Macintosh HD" GPT /dev/diskX

# 3. Restaure o Volume Group de origem (ROSV: System + Data + Preboot + Recovery)
sudo asr restore --source "<volume_origem>" --target "/Volumes/Macintosh HD" --erase
```

> **Atenção:** confira com `diskutil list` antes de rodar `eraseDisk` ou `asr restore` para não apagar o SSD interno (`/dev/disk0` / `/dev/disk3`).

### 1.4 Layout APFS resultante no M4 Pro
- **NVMe Externo (`/dev/disk4` / container APFS `/dev/disk5`):**
  - Volume Group UUID: `973F8359-F648-49B3-9811-7E9DC38F4A9F`
  - `Macintosh HD` (`/dev/disk5s1`, snapshot selado `disk5s1s1` — Sistema)
  - `Macintosh HD - Data` (`/dev/disk5s2` — Dados)
  - `Preboot` (`/dev/disk5s3`)
  - `Recovery` (`/dev/disk5s4`)
  - `VM` (`/dev/disk5s5`)
- **SSD Interno do M4 Pro (`/dev/disk0` / container APFS `/dev/disk3`):**
  - Volume de dados nomeado `Data` (`/dev/disk3s5`) — mantido 100% intacto.

---

## Etapa 2 — Habilitando o NVMe Externo como Disco Inicializável (`LocalPolicy` / `Preboot`)

> **Obrigatório nos DOIS Macs (M3 Pro e M4 Pro) após o clone:** o **Restaurar** do Utilitário de Disco copia e monta o Volume Group APFS no NVMe externo, mas **não** registra a assinatura criptográfica (`LocalPolicy`) no container interno `iSCPreboot` de nenhum Mac. Sem essa assinatura registrada internamente pelo **Secure Enclave** de cada máquina, o NVMe externo **não é reconhecido como disco inicializável** (nem em *Ajustes do Sistema > Geral > Disco de Inicialização* nem nas *Opções de Inicialização*).

Existem **duas camadas** envolvidas no reconhecimento do disco:

1. **`iSCPreboot` interno de cada Mac (`/System/Volumes/iSCPreboot/<VolumeGroupUUID>/LocalPolicy/`):**
   Fica no container interno `Apple_APFS_ISC` (`disk0s1`) do próprio Mac. Contém os arquivos `*.img4` e `*.recovery.img4` assinados pelo **Secure Enclave** daquela máquina específica (vinculados ao `CHIP`, `ECID`, `vuid` e `nsih`). Como essa assinatura é interna de cada hardware, ela **precisa ser registrada uma vez no M3 Pro e uma vez no M4 Pro** — e gravar em um não sobrescreve o outro.
2. **`Preboot` e `Recovery` do próprio NVMe externo (`disk5s3` e `disk5s4`):**
   Guardam os manifests de boot e correlação de usuários em `/System/Volumes/Preboot/<VolumeGroupUUID>/boot/<nsih>` e `/Volumes/Recovery/<VolumeGroupUUID>/boot/`.

### Passos e comandos para registrar a assinatura interna e habilitar o boot (executar em cada Mac)

1. **Identifique na seção `external` o dispositivo `System` (`Macintosh HD`, ex.: `disk5s1`) e o `Volume Group UUID` (ex.: `973F8359-F648-49B3-9811-7E9DC38F4A9F`) do NVMe externo:**
   ```sh
   diskutil list external
   diskutil apfs listVolumeGroups
   ```

2. **Monte o volume `Macintosh HD` do disco externo (se ainda não estiver montado):**
   ```sh
   sudo diskutil mount /dev/disk5s1
   diskutil info /dev/disk5s1 | grep "Mount Point"
   ```
   *(Se o SSD interno já estiver montado, confira o `Mount Point` exato retornado para o `Macintosh HD` do disco externo para não apontar o `bless` para o disco errado.)*

3. **Atualize o `Preboot` do volume externo clonado (sincroniza usuários APFS/FileVault e Open Directory):**
   *(Substitua `disk5s1` pelo identificador retornado no passo 1)*
   ```sh
   sudo diskutil apfs updatePreboot /dev/disk5s1
   ```

4. **Gere e assine no Secure Enclave a `LocalPolicy` (`Full Security`) dentro do `iSCPreboot` interno deste Mac:**
   ```sh
   sudo bputil -f -v <VolumeGroupUUID>
   ```
   *(Solicita usuário administrador e senha do volume para assinar e gravar `*.img4` e `*.recovery.img4` em `/System/Volumes/iSCPreboot/<VolumeGroupUUID>/LocalPolicy/`, mantendo o **SIP ativado**.)*

5. **Abençoe (`bless`) o `Macintosh HD` do disco externo para registrá-lo como disco inicializável:**
   *(Use o `Mount Point` do `Macintosh HD` externo obtido no passo 2)*
   ```sh
   sudo bless --mount "<Mount Point do Macintosh HD externo>" --setBoot
   ```
   *(Se precisar recriar/selar o snapshot de boot: `sudo bless --mount "<Mount Point do Macintosh HD externo>/System/Library/CoreServices" --setBoot --create-snapshot`.)*

6. **Verifique se a assinatura interna foi registrada e se o disco passou a ser reconhecido:**
   ```sh
   ls -la /System/Volumes/iSCPreboot/<VolumeGroupUUID>/LocalPolicy/
   ls -la /System/Volumes/Preboot/<VolumeGroupUUID>/boot/
   sudo bputil -d -v <VolumeGroupUUID>
   ```
   Confirme também em **Ajustes do Sistema > Geral > Disco de Inicialização** (ou nas **Opções de Inicialização** segurando o botão Power ao ligar). *(Se o macOS solicitar confirmação de proprietário para assinar a nova `LocalPolicy` na interface, autentique com o usuário administrador em Disco de Inicialização / Modo Recovery.)*

7. **Repita os passos 1 a 6 no segundo Mac:**
   Conecte o NVMe externo no outro Mac (M4 Pro / M3 Pro) inicializado pelo SSD interno e execute os mesmos passos para que **ambos** possuam a assinatura `LocalPolicy` desse `Volume Group UUID` gravada no próprio `iSCPreboot` interno.

---

## Etapa 3 — Desbloqueando Siri AI / Apple Intelligence

### 3.1 Causa raiz
O daemon `/usr/libexec/eligibilityd` chama `+[ExternalBootDriveInput queryHasExternalBootDrive]`, lê `external-boot = <01000000>` em `IODeviceTree:/chosen` e marca o sistema como inelegível (`OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE = 2` e `os_eligibility_answer_t = 2`) em dois arquivos XML:

- `/private/var/db/eligibilityd/eligibility.plist`
  - `OS_ELIGIBILITY_DOMAIN_GREYMATTER`
  - `OS_ELIGIBILITY_DOMAIN_AMERICIUM`
- `/private/var/db/os_eligibility/eligibility.plist`
  - `OS_ELIGIBILITY_DOMAIN_SIRI_MODE`
  - `OS_ELIGIBILITY_DOMAIN_XCODE_LLM`
  - `OS_ELIGIBILITY_DOMAIN_SWIFT_ASSIST`

Com o **SIP ativado** no macOS normal, até `root` (`sudo`) recebe `Operation not permitted` ao tentar gravar nesses diretórios porque `codesign -d --entitlements - /usr/libexec/eligibilityd` exige as entitlements privadas `com.apple.private.security.storage.eligibilityd` e `com.apple.private.security.storage.os_eligibility.readwrite`.

### 3.2 Por que executar via `/bin/sh` no Modo Recovery
Inspecionando a imagem real do Modo Recovery (`arm64eBaseSystem.dmg`):
- **Não existem `python3` nem `zsh`** no Recovery (e o `python3` do Homebrew no volume de dados falha porque busca bibliotecas em `/opt/homebrew/...` na raiz `/`).
- O volume de dados externo fica montado em **`/Volumes/Macintosh HD - Data`** (e não em `/`).
- `/bin/sh`, `/usr/libexec/PlistBuddy`, `/usr/bin/chflags` e `/bin/cp` **existem nativamente** no `arm64eBaseSystem.dmg`.
- No Modo Recovery, o runtime não bloqueia a edição dos arquivos dentro de `/Volumes/Macintosh HD - Data`, permitindo aplicar o patch **sem desativar o SIP** (`csrutil disable` não é necessário) e travar os arquivos com `chflags uchg`.

### 3.3 Como aplicar com o script [`fix_siri.sh`](./fix_siri.sh)

> **Obrigatório no Modo Recovery:** ao entrar no Recovery, os volumes do NVMe externo **não vêm montados automaticamente**. Monte **`Macintosh HD` e `Macintosh HD - Data` do DISCO EXTERNO** (atenção para não confundir com o `Macintosh HD` do disco interno) antes de executar qualquer comando.

1. Reinicie o Mac para o **Modo Recovery** (mantenha o botão Power pressionado ao ligar > **Opções**).
2. **Monte o `Macintosh HD` e o `Macintosh HD - Data` do DISCO EXTERNO** (escolha uma das duas formas):
   - **Pelo Utilitário de Disco (interface):** abra **Utilitário de Disco**, vá na seção **Externo**, selecione **`Macintosh HD`** e clique em **Montar**, depois selecione **`Macintosh HD - Data`** e clique em **Montar** (informe a senha se solicitada). Feche o Utilitário de Disco e abra **Utilitários > Terminal**.
   - **Ou direto pelo Terminal do Recovery:** abra **Utilitários > Terminal** e rode:
     ```sh
     # 1. Liste os discos externos e identifique "Macintosh HD" (ex.: disk5s1) e "Macintosh HD - Data" (ex.: disk5s2):
     diskutil list external

     # 2. Monte o "Macintosh HD" e o "Macintosh HD - Data" do DISCO EXTERNO:
     diskutil mount /dev/disk5s1
     diskutil mount /dev/disk5s2
     # Se estiver com FileVault ativado (criptografado), use unlockVolume no lugar:
     diskutil apfs unlockVolume /dev/disk5s1
     diskutil apfs unlockVolume /dev/disk5s2

     # 3. Confirme os volumes externos montados em /Volumes:
     ls -la "/Volumes/Macintosh HD - Data"
     ```
3. Com o disco externo montado, execute o script:
   ```sh
   sh "/Volumes/Macintosh HD - Data/Users/<seu-usuario>/ml/macos-nvme-external-clone/fix_siri.sh"
   ```
4. Reinicie de volta para o macOS normal no NVMe externo.

### 3.4 Comandos manuais equivalentes (o que fazer no Terminal do Recovery)
```sh
# 1. Monte "Macintosh HD" e "Macintosh HD - Data" do DISCO EXTERNO antes (confira com diskutil list external):
diskutil mount /dev/disk5s1
diskutil mount /dev/disk5s2
# (Se tiver FileVault: diskutil apfs unlockVolume /dev/disk5s1 && diskutil apfs unlockVolume /dev/disk5s2)

# 2. Defina os caminhos dentro do volume montado e aplique o patch:
TARGET="/Volumes/Macintosh HD - Data"
P1="$TARGET/private/var/db/eligibilityd/eligibility.plist"
P2="$TARGET/private/var/db/os_eligibility/eligibility.plist"

/usr/bin/chflags nouchg "$P1" "$P2" 2>/dev/null || true
cp -p "$P1" "$P1.bak"
cp -p "$P2" "$P2.bak"

/usr/libexec/PlistBuddy \
  -c "Set :OS_ELIGIBILITY_DOMAIN_GREYMATTER:status:OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE 3" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_GREYMATTER:os_eligibility_answer_t 4" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_AMERICIUM:status:OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE 3" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_AMERICIUM:os_eligibility_answer_t 4" \
  "$P1"

/usr/libexec/PlistBuddy \
  -c "Set :OS_ELIGIBILITY_DOMAIN_SIRI_MODE:status:OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE 3" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_SIRI_MODE:os_eligibility_answer_t 4" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_XCODE_LLM:status:OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE 3" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_XCODE_LLM:os_eligibility_answer_t 4" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_SWIFT_ASSIST:status:OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE 3" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_SWIFT_ASSIST:os_eligibility_answer_t 4" \
  "$P2"

/usr/bin/chflags uchg "$P1" "$P2"
```

### 3.5 Verificação após voltar ao macOS normal
```sh
csrutil status
ls -laO /private/var/db/eligibilityd/eligibility.plist /private/var/db/os_eligibility/eligibility.plist
/usr/libexec/PlistBuddy \
  -c "Print :OS_ELIGIBILITY_DOMAIN_GREYMATTER:os_eligibility_answer_t" \
  -c "Print :OS_ELIGIBILITY_DOMAIN_AMERICIUM:os_eligibility_answer_t" \
  /private/var/db/eligibilityd/eligibility.plist
/usr/libexec/PlistBuddy \
  -c "Print :OS_ELIGIBILITY_DOMAIN_SIRI_MODE:os_eligibility_answer_t" \
  -c "Print :OS_ELIGIBILITY_DOMAIN_XCODE_LLM:os_eligibility_answer_t" \
  -c "Print :OS_ELIGIBILITY_DOMAIN_SWIFT_ASSIST:os_eligibility_answer_t" \
  /private/var/db/os_eligibility/eligibility.plist
```
Resultado esperado:
- `System Integrity Protection status: enabled.`
- Ambos os arquivos com a flag `uchg`.
- Todos os cinco valores imprimindo `4`.

---

## Etapa 4 — Corrigindo o Espelhamento do iPhone (`iPhone Mirroring` / `ScreenContinuity`)

### 4.1 Causa raiz
Ao clonar de um Mac para outro (M3 Pro → M4 Pro) e dar boot no novo hardware, o banco SQLite do `replicatord` permanece com a relação criptográfica anterior presa em estado `pairing` (`State = 1`):
- `~/Library/Group Containers/group.com.apple.replicatord/replicatord/replicatord.sql`
- `~/Library/Containers/com.apple.ScreenContinuity/Data/Library/Preferences/com.apple.ScreenContinuity.plist`

Isso faz o `replicatord` responder `Sending disabled handshake response` e o `iPhone Mirroring.app` abortar no Passo 5 (`5. Checking if Replicator has a device paired`) com erro `noCompatiblePhone`.

### 4.2 Como corrigir com [`fix_iphone_mirroring.sh`](./fix_iphone_mirroring.sh)
No Terminal do macOS normal (não precisa reiniciar nem entrar no Recovery):

```sh
sh "./fix_iphone_mirroring.sh"
```

### 4.3 Comandos manuais equivalentes
```sh
REP_DIR="$HOME/Library/Group Containers/group.com.apple.replicatord/replicatord"
PREF_FILE="$HOME/Library/Containers/com.apple.ScreenContinuity/Data/Library/Preferences/com.apple.ScreenContinuity.plist"
BACKUP_DIR="$REP_DIR/backup_$(date +"%Y%m%d_%H%M%S")"

mkdir -p "$BACKUP_DIR"
cp -p "$REP_DIR"/replicatord.sql* "$BACKUP_DIR/" 2>/dev/null || true
cp -p "$PREF_FILE" "$BACKUP_DIR/" 2>/dev/null || true

rm -f "$REP_DIR"/replicatord.sql* "$PREF_FILE"

killall replicatord sharingd rapportd ContinuityCaptureAgent 2>/dev/null || true
```

Em seguida, abra o **Espelhamento do iPhone** (`open -a "iPhone Mirroring"`) e conclua o pareamento na tela.

### 4.4 Verificação nos logs (opcional)
```sh
/usr/bin/log show --last 5m --predicate 'process == "replicatord" OR process == "iPhone Mirroring"' --info --style compact | tail -n 50
```

---

## Etapa 5 — Alternando o Mesmo NVMe Externo entre M3 Pro e M4 Pro

| Recurso | Comportamento ao plugar no M3 Pro (ou voltar ao M4 Pro) | Ação necessária |
|---|---|---|
| **Boot do macOS** | Funciona livremente nos dois Macs após a Etapa 2 | Após o clone, a **Etapa 2 deve ser executada uma vez nos DOIS Macs (M3 Pro e M4 Pro)** para registrar a assinatura `LocalPolicy` no `iSCPreboot` interno (`/System/Volumes/iSCPreboot/<VolumeGroupUUID>/LocalPolicy/`) de cada máquina. Depois que ambos possuem a assinatura gravada, o NVMe externo inicializa diretamente nos dois (caso aplique uma atualização de sistema em um Mac, pode ser necessário revalidar no outro). |
| **Siri AI / Apple Intelligence** | Funciona automaticamente nos dois Macs | Os dois `eligibility.plist` ficam no volume compartilhado `Macintosh HD - Data` travados com `chflags uchg`. |
| **Espelhamento do iPhone** | Pode exigir novo pareamento ao trocar de Mac | O `replicatord.sql` guarda o vínculo com o hardware/Secure Enclave do último Mac usado. Se ficar preso tentando conectar ao trocar de máquina, rode `sh "./fix_iphone_mirroring.sh"`. |
