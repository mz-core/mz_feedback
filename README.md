# mz_feedback

Recurso de feedback para players com formulario NUI, texto, imagens otimizadas e painel de leitura para a staff.

## Uso

- `/feedback` ou `F10`: abre o formulario do player.
- `/feedbacks`: abre a fila da staff.
- O lembrete do comando fica permanentemente no canto inferior esquerdo.
- O player pode selecionar arquivos ou capturar a tela atual do jogo.

O painel da staff usa a permissao global `staff.panel.open` do `mz_core`.

## Protecoes

- Texto entre 20 e 2.000 caracteres.
- Ate 3 imagens JPG, PNG ou WEBP.
- A interface limita a imagem original a 8 MB e redimensiona para ate 1600x1200.
- Cada imagem enviada ao servidor fica limitada a 350 KB.
- Soma maxima das imagens: 900 KB.
- O servidor revalida MIME, Base64, assinatura real do arquivo, tamanho e quantidade.
- Intervalo de 120 segundos e limite de 5 envios por player a cada hora.
- Transferencias grandes usam eventos latentes para nao congestionar a rede.
- Consultas da staff carregam as fotos apenas quando um feedback e aberto.

Todos os limites podem ser alterados em `shared/config.lua`. As tabelas sao criadas automaticamente; `sql/install.sql` existe para instalacao manual.
