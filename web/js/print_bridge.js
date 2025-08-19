function callJsPrint(html) {
  const printWindow = window.open('', '_blank', 'width=400,height=600');
  printWindow.document.write(html);
  printWindow.document.close();
  printWindow.focus();
  printWindow.print();
}
