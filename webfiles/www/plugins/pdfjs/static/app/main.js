kodReady.push(function(){
	if( !$.supportCanvas() ){
		return;
	}
	kodApp.remove('pdfView');
	kodApp.add({
		name:"pdfjs",
		title:"PDF Viewer",
		ext:"{{config.fileExt}}",
		sort:"{{config.fileSort}}",
		icon:'{{pluginHost}}static/app/images/icon.png',
		callback:function(path,ext){
			var url = '{{pluginApi}}&path='+core.pathCommon(path);
			if('window' == "{{config.openWith}}" && !core.isFileView() ){
				window.open(url);
			}else{
				core.openDialog(url,core.icon(ext),htmlEncode(core.pathThis(path)));
			}
		}
	});
	$.addStyle(
	".x-item-file.x-ofd{\
		background-image:url('{{pluginHost}}static/ofd/img/icon.png');\
	}");
});
