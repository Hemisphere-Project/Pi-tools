<?php

class pdfjsPlugin extends PluginBase{
	function __construct(){
		parent::__construct();
	}
	public function regiest(){
		$this->hookRegiest(array(
			'user.commonJs.insert' => 'pdfjsPlugin.echoJs',
		));
	}
	public function echoJs($st,$act){
		if($this->isFileExtence($st,$act)){
			$this->echoFile('static/app/main.js');
		}
	}
	public function index(){
		$path = $this->filePath($this->in['path']);
		$fileUrl  = _make_file_proxy($path);
		$fileName = get_path_this(rawurldecode($this->in['path']));
		$fileName.= ' - '.LNG('kod_name').LNG('kod_power_by');
		$ext = get_path_ext($this->in['path']);
		$ext = preg_replace("/\(\d*?\)/", '', $ext);

		if( in_array($ext,array('pdf','djvu','ofd')) ){
			include($this->pluginPath.'/php/'.$ext.'.php');
		}
	}
}