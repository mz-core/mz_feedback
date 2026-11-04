(() => {
  'use strict';

  const DEFAULT_CONFIG = {
    command: 'feedback',
    textMinLength: 20,
    textMaxLength: 2000,
    maxImages: 3,
    maxImageBytes: 350 * 1024,
    maxTotalImageBytes: 900 * 1024,
    maxSourceImageBytes: 8 * 1024 * 1024,
    maxImageWidth: 1600,
    maxImageHeight: 1200,
    categories: {
      bug: 'Problema / bug',
      suggestion: 'Sugestão',
      gameplay: 'Jogabilidade',
      other: 'Outro'
    },
    statuses: {
      new: 'Novo',
      reviewing: 'Em análise',
      resolved: 'Resolvido',
      rejected: 'Arquivado'
    }
  };

  let config = { ...DEFAULT_CONFIG };
  let selectedImages = [];
  let reports = [];
  let selectedReportId = null;
  let submitting = false;
  const isNui = typeof window.GetParentResourceName === 'function';

  const $ = (selector) => document.querySelector(selector);
  const overlay = $('#overlay');
  const shell = $('.shell');
  const submitScreen = $('#submit-screen');
  const staffScreen = $('#staff-screen');
  const form = $('#feedback-form');
  const category = $('#category');
  const message = $('#message');
  const textCounter = $('#text-counter');
  const imageInput = $('#image-input');
  const imageList = $('#image-list');
  const addImagesButton = $('#add-images');
  const captureScreenButton = $('#capture-screen');
  const submitButton = $('#submit-button');
  const formError = $('#form-error');
  const statusFilter = $('#status-filter');
  const reportList = $('#report-list');
  const reportDetail = $('#report-detail');

  const nui = async (eventName, data = {}) => {
    if (!isNui) {
      return { ok: true, pending: eventName === 'submit' };
    }

    const response = await fetch(`https://${window.GetParentResourceName()}/${eventName}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data)
    });
    return response.json();
  };

  const escapeHtml = (value) => String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');

  const humanBytes = (bytes) => `${Math.max(1, Math.round(Number(bytes || 0) / 1024))} KB`;

  const showError = (text) => {
    formError.textContent = text;
    formError.hidden = !text;
  };

  const formatDate = (value) => {
    if (!value) return '';
    const parsed = new Date(String(value).replace(' ', 'T'));
    return Number.isNaN(parsed.getTime()) ? String(value) : parsed.toLocaleString('pt-BR');
  };

  const setConfig = (incoming = {}) => {
    config = { ...DEFAULT_CONFIG, ...incoming };
    $('#hint-command').textContent = `/${config.command}`;
    textCounter.textContent = `${message.value.length} / ${config.textMaxLength}`;
    message.maxLength = config.textMaxLength;
    $('#upload-help').textContent = `Opcional · até ${config.maxImages} fotos · ${humanBytes(config.maxImageBytes)} cada`;

    category.innerHTML = Object.entries(config.categories)
      .map(([value, label]) => `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`)
      .join('');

    statusFilter.innerHTML = '<option value="">Todos</option>' + Object.entries(config.statuses)
      .map(([value, label]) => `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`)
      .join('');
  };

  const open = (mode, incomingConfig) => {
    setConfig(incomingConfig);
    overlay.hidden = false;
    const isStaff = mode === 'staff';
    shell.classList.toggle('staff-mode', isStaff);
    submitScreen.hidden = isStaff;
    staffScreen.hidden = !isStaff;
    $('#screen-title').textContent = isStaff ? 'Feedbacks da comunidade' : 'Enviar feedback';
    $('#screen-subtitle').textContent = isStaff
      ? 'Analise relatos, consulte imagens e acompanhe cada atendimento.'
      : 'Conte o que aconteceu. Imagens ajudam a equipe a entender melhor.';

    if (!isStaff) {
      window.setTimeout(() => message.focus(), 50);
    }
  };

  const close = () => {
    overlay.hidden = true;
    submitting = false;
    submitButton.disabled = false;
    submitButton.querySelector('span').textContent = 'Enviar feedback';
    nui('close');
  };

  const resetForm = () => {
    form.reset();
    selectedImages = [];
    showError('');
    renderImages();
    textCounter.textContent = `0 / ${config.textMaxLength}`;
  };

  const dataUrlBytes = (dataUrl) => {
    const base64 = String(dataUrl).split(',')[1] || '';
    const padding = base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0;
    return Math.floor(base64.length * 3 / 4) - padding;
  };

  const canvasToDataUrl = (canvas, quality) => canvas.toDataURL('image/jpeg', quality);

  const optimizeImage = async (file, fallbackName = 'imagem.jpg') => {
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      throw new Error('Use apenas imagens JPG, PNG ou WEBP.');
    }
    if (file.size > config.maxSourceImageBytes) {
      throw new Error(`A foto original deve ter no máximo ${humanBytes(config.maxSourceImageBytes)}.`);
    }

    const bitmap = await createImageBitmap(file);
    let scale = Math.min(1, config.maxImageWidth / bitmap.width, config.maxImageHeight / bitmap.height);
    let width = Math.max(1, Math.round(bitmap.width * scale));
    let height = Math.max(1, Math.round(bitmap.height * scale));
    const canvas = document.createElement('canvas');
    const context = canvas.getContext('2d', { alpha: false });
    let quality = 0.84;
    let dataUrl = '';

    for (let attempt = 0; attempt < 8; attempt += 1) {
      canvas.width = width;
      canvas.height = height;
      context.fillStyle = '#000';
      context.fillRect(0, 0, width, height);
      context.drawImage(bitmap, 0, 0, width, height);
      dataUrl = canvasToDataUrl(canvas, quality);

      if (dataUrlBytes(dataUrl) <= config.maxImageBytes) break;
      if (quality > 0.58) {
        quality -= 0.1;
      } else {
        width = Math.max(640, Math.round(width * 0.82));
        height = Math.max(360, Math.round(height * 0.82));
      }
    }

    bitmap.close();
    const byteSize = dataUrlBytes(dataUrl);
    if (byteSize > config.maxImageBytes) {
      throw new Error(`Não foi possível reduzir a foto para ${humanBytes(config.maxImageBytes)}.`);
    }

    return { dataUrl, byteSize, name: file.name || fallbackName };
  };

  const renderImages = () => {
    addImagesButton.disabled = selectedImages.length >= config.maxImages;
    captureScreenButton.disabled = selectedImages.length >= config.maxImages;
    if (!selectedImages.length) {
      imageList.innerHTML = '<div class="empty-images"><span>▧</span><p>Nenhuma imagem adicionada</p></div>';
      return;
    }

    imageList.innerHTML = selectedImages.map((image, index) => `
      <figure class="image-card">
        <img src="${image.dataUrl}" alt="Imagem ${index + 1} selecionada">
        <button type="button" data-remove-image="${index}" aria-label="Remover imagem ${index + 1}">×</button>
        <figcaption class="image-size">${humanBytes(image.byteSize)}</figcaption>
      </figure>
    `).join('');
  };

  const addFiles = async (files) => {
    showError('');
    const available = config.maxImages - selectedImages.length;
    if (available <= 0) {
      showError(`O limite é de ${config.maxImages} imagens.`);
      return;
    }

    addImagesButton.disabled = true;
    addImagesButton.textContent = 'Otimizando…';
    try {
      for (const file of Array.from(files).slice(0, available)) {
        const image = await optimizeImage(file);
        const total = selectedImages.reduce((sum, item) => sum + item.byteSize, 0) + image.byteSize;
        if (total > config.maxTotalImageBytes) {
          throw new Error(`As fotos podem somar no máximo ${humanBytes(config.maxTotalImageBytes)}.`);
        }
        selectedImages.push(image);
        renderImages();
      }
    } catch (error) {
      showError(error instanceof Error ? error.message : 'Não foi possível processar a imagem.');
    } finally {
      addImagesButton.textContent = 'Adicionar fotos';
      addImagesButton.disabled = selectedImages.length >= config.maxImages;
      imageInput.value = '';
    }
  };

  const addCapturedScreen = async () => {
    showError('');
    if (selectedImages.length >= config.maxImages) {
      showError(`O limite é de ${config.maxImages} imagens.`);
      return;
    }

    captureScreenButton.disabled = true;
    captureScreenButton.textContent = 'Capturando…';
    try {
      const response = await nui('captureScreenshot');
      if (!response.ok || !response.dataUrl) {
        throw new Error(response.message || 'Não foi possível capturar a tela.');
      }

      const source = await fetch(response.dataUrl);
      const blob = await source.blob();
      const image = await optimizeImage(blob, 'captura.jpg');
      const total = selectedImages.reduce((sum, item) => sum + item.byteSize, 0) + image.byteSize;
      if (total > config.maxTotalImageBytes) {
        throw new Error(`As fotos podem somar no máximo ${humanBytes(config.maxTotalImageBytes)}.`);
      }
      selectedImages.push(image);
      renderImages();
    } catch (error) {
      showError(error instanceof Error ? error.message : 'Não foi possível capturar a tela.');
    } finally {
      captureScreenButton.textContent = 'Capturar tela';
      captureScreenButton.disabled = selectedImages.length >= config.maxImages;
    }
  };

  const renderReports = () => {
    const filter = statusFilter.value;
    const visible = filter ? reports.filter((report) => report.status === filter) : reports;
    if (!visible.length) {
      reportList.innerHTML = '<p class="loading-state">Nenhum feedback encontrado.</p>';
      return;
    }

    reportList.innerHTML = visible.map((report) => `
      <button class="report-card ${Number(report.id) === Number(selectedReportId) ? 'active' : ''}" type="button" data-report-id="${Number(report.id)}">
        <div class="report-card-head">
          <strong>#${Number(report.id)} · ${escapeHtml(report.player_name || `Conta ${report.account_id}`)}</strong>
          <span class="status-pill" data-status="${escapeHtml(report.status)}">${escapeHtml(config.statuses[report.status] || report.status)}</span>
        </div>
        <p>${escapeHtml(report.message)}</p>
        <div class="report-meta">
          <span>${escapeHtml(config.categories[report.category] || report.category)}</span>
          <span>${Number(report.image_count || 0)} foto(s)</span>
        </div>
      </button>
    `).join('');
  };

  const renderDetail = (report) => {
    if (!report) return;
    selectedReportId = Number(report.id);
    renderReports();

    const images = Array.isArray(report.images) ? report.images : [];
    const statusOptions = Object.entries(config.statuses).map(([value, label]) =>
      `<option value="${escapeHtml(value)}" ${value === report.status ? 'selected' : ''}>${escapeHtml(label)}</option>`
    ).join('');

    reportDetail.innerHTML = `
      <div class="detail-meta">
        <span>${escapeHtml(report.player_name || `Conta ${report.account_id}`)} · conta #${escapeHtml(report.account_id)} · personagem #${escapeHtml(report.character_id || '—')}</span>
        <span>${escapeHtml(formatDate(report.created_at))}</span>
      </div>
      <h2 class="detail-title">#${Number(report.id)} · ${escapeHtml(config.categories[report.category] || report.category)}</h2>
      <p class="detail-message">${escapeHtml(report.message)}</p>
      <div class="detail-actions">
        <label>
          <span class="eyebrow">STATUS</span>
          <select id="detail-status" data-status-id="${Number(report.id)}">${statusOptions}</select>
        </label>
      </div>
      ${images.length ? `
        <div class="detail-gallery">
          ${images.map((image, index) => `
            <a href="${image.image_data}" target="_blank" rel="noopener" title="Abrir imagem ${index + 1}">
              <img src="${image.image_data}" alt="Anexo ${index + 1} do feedback">
            </a>
          `).join('')}
        </div>
      ` : ''}
    `;
  };

  $('#close-button').addEventListener('click', close);
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !overlay.hidden) close();
  });

  message.addEventListener('input', () => {
    textCounter.textContent = `${message.value.length} / ${config.textMaxLength}`;
  });

  addImagesButton.addEventListener('click', () => imageInput.click());
  captureScreenButton.addEventListener('click', addCapturedScreen);
  imageInput.addEventListener('change', () => addFiles(imageInput.files));
  imageList.addEventListener('click', (event) => {
    const button = event.target.closest('[data-remove-image]');
    if (!button) return;
    selectedImages.splice(Number(button.dataset.removeImage), 1);
    renderImages();
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (submitting) return;

    const normalizedMessage = message.value.trim();
    if (normalizedMessage.length < config.textMinLength) {
      showError(`Escreva pelo menos ${config.textMinLength} caracteres.`);
      message.focus();
      return;
    }

    submitting = true;
    showError('');
    submitButton.disabled = true;
    submitButton.querySelector('span').textContent = 'Enviando…';

    try {
      const response = await nui('submit', {
        category: category.value,
        message: normalizedMessage,
        images: selectedImages.map((image) => image.dataUrl)
      });
      if (!response.ok) {
        throw new Error(response.message || 'Não foi possível enviar o feedback.');
      }
      if (!isNui) {
        resetForm();
        close();
      }
    } catch (error) {
      submitting = false;
      submitButton.disabled = false;
      submitButton.querySelector('span').textContent = 'Enviar feedback';
      showError(error instanceof Error ? error.message : 'Não foi possível enviar o feedback.');
    }
  });

  statusFilter.addEventListener('change', renderReports);
  reportList.addEventListener('click', (event) => {
    const card = event.target.closest('[data-report-id]');
    if (!card) return;
    selectedReportId = Number(card.dataset.reportId);
    renderReports();
    reportDetail.innerHTML = '<p class="loading-state">Carregando detalhes…</p>';
    nui('requestDetail', { id: selectedReportId });
  });

  reportDetail.addEventListener('change', (event) => {
    const select = event.target.closest('[data-status-id]');
    if (!select) return;
    nui('updateStatus', { id: Number(select.dataset.statusId), status: select.value });
  });

  window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'boot') {
      $('#hint-command').textContent = `/${data.command || 'feedback'}`;
      $('#hint-key').textContent = data.key || 'F10';
    } else if (data.action === 'open') {
      open(data.mode, data.config);
    } else if (data.action === 'close') {
      overlay.hidden = true;
    } else if (data.action === 'submissionResult') {
      if (data.result?.ok) {
        resetForm();
      } else {
        submitting = false;
        submitButton.disabled = false;
        submitButton.querySelector('span').textContent = 'Enviar feedback';
        showError(data.result?.message || 'Não foi possível enviar o feedback.');
      }
    } else if (data.action === 'staffList') {
      reports = Array.isArray(data.rows) ? data.rows : [];
      renderReports();
    } else if (data.action === 'staffDetail') {
      renderDetail(data.report);
    } else if (data.action === 'statusResult') {
      const changed = reports.find((report) => Number(report.id) === Number(data.result?.id));
      if (changed) changed.status = data.result.status;
      renderReports();
    }
  });

  setConfig();
  renderImages();

  const previewParams = new URLSearchParams(window.location.search);
  if (!isNui && previewParams.get('preview') === '1') {
    const previewStaff = previewParams.get('staff') === '1';
    open(previewStaff ? 'staff' : 'submit');
    if (previewStaff) {
      reports = [
        {
          id: 1042,
          account_id: 291,
          character_id: 12,
          player_name: 'Alex Ferreira',
          category: 'bug',
          message: 'Ao guardar o veículo na garagem central, ele continua aparecendo na rua.',
          status: 'new',
          image_count: 2,
          created_at: new Date().toISOString()
        },
        {
          id: 1041,
          account_id: 187,
          character_id: 18,
          player_name: 'Marina Costa',
          category: 'suggestion',
          message: 'Seria legal ter mais opções de organização para os eventos da comunidade.',
          status: 'reviewing',
          image_count: 0,
          created_at: new Date().toISOString()
        }
      ];
      renderReports();
    }
  }
})();
