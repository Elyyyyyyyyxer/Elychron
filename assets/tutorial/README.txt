教程图片放这里，一个教程一个子目录：

    assets/tutorial/tasks/types.png      ← 待办教程里的"四种类型"截图
    assets/tutorial/focus/main.png

不用改 pubspec.yaml（它已声明整个 assets/ 目录）。
路径写在教程内容文件里（lib/tutorial/modules/*.dart 的 TutorialImageStep.asset）。
图片还没准备好也没关系：播放器会显示占位框并写出期望路径。