//----------------------------------------------------------------------
$(function () {
//----------------------------------------------------------------------
  let lastSelectedItem = null;

  $("#search").autocomplete({
    source: function (request, response) {
      $.ajax({
        url: "/autocomplete/birds.json", // adjust this path to your backend
        data: { term: request.term },
        success: function (data) {
          response(data); // expect array of { label, image_url }
        }
      });
    },
    focus: function (event, ui) {
      event.preventDefault();
      $("#search").val(ui.item.label);
    },
    select: function (event, ui) {
      event.preventDefault();
      $("#search").val(ui.item.label);
      showBirdCard(ui.item);
    },
    minLength: 2
  });

//----------------------------------------------------------------------
  function showBirdCard(item) {
//----------------------------------------------------------------------
    if (item && item.label) {
      const birdName = item.label.replace(/"/g, '&quot;');

      let filename = item.label.toLowerCase()
        .replace(/\s+/g, '_')
        .replace(/-/g, '') + '.png';

      const imageUrl = `/birds/img/${filename}`; // update path if needed

      const cardHtml = `
        <div class="bird-card">
          <img src="${imageUrl}" alt="${birdName}">
          <div class="bird-caption">${birdName}</div>
        </div>
      `;

      $("#bird-images").html(cardHtml);
    } else {
      $("#bird-images").html(`<p>No image available.</p>`);
    }
  }
});
