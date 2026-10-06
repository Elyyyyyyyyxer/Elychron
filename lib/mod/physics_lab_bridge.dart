const physicsLabReadScript = r'''
(function(){
  const result = {state: 'pending'};
  window.__elychronPhysics = result;
  const finish = value => { if (window.__elychronPhysics === result) window.__elychronPhysics = value; };
  const wait = () => new Promise(resolve => setTimeout(resolve, 100));
  function findStudent() {
    const seen = new Set();
    const nodes = Array.from(document.querySelectorAll('[id]')).map(n => n.__vue__).filter(Boolean);
    while (nodes.length && seen.size < 500) {
      const node = nodes.shift();
      if (seen.has(node)) continue;
      seen.add(node);
      if (node.$options && node.$options.name === 'studentCourse') return node;
      nodes.push(...(node.$children || []));
    }
    return null;
  }
  (async function(){
    if (location.host !== '10.203.16.55:86') { finish({state:'error'}); return; }
    let student;
    for (let i = 0; i < 60; i++) {
      if (location.pathname.endsWith('/login') || !localStorage.getItem('Authorization')) {
        finish({state:'login'}); return;
      }
      student = findStudent();
      if (student && student.user && student.user.username && student.currentTerm && student.currentTerm.id) break;
      await wait();
    }
    if (!student || !student.user || !student.user.username || !student.currentTerm || !student.currentTerm.id || typeof student.emitAjax !== 'function') {
      finish({state:'error'}); return;
    }
    // 使用官网自身的认证与签名函数；只调用当前学生课表的三个只读端点。
    function get(path, data) {
      return new Promise((resolve,reject) => student.emitAjax({path, data, type:'GET',
        success:resolve, error:() => reject(Error('request'))}));
    }
    const authorization = localStorage.getItem('Authorization');
    const uid = student.user.username;
    const termId = student.currentTerm.id;
    const courses = await get('/api/courses/uid', {uid,termId,page:-1,size:-1});
    if (!Array.isArray(courses)) throw Error('shape');
    const rows = [];
    for (const course of courses) {
      if (course.id == null) throw Error('shape');
      const data = {uid,termId,courseId:course.id,page:-1,size:-1};
      let selected = await get('/api/course/lab/students/full',data);
      if (!selected || !Array.isArray(selected.content)) throw Error('shape');
      const entries = [...selected.content];
      const pages = Number(selected.totalPages || 1);
      if (pages > 100) throw Error('pages');
      for (let page = 1; page < pages; page++) {
        selected = await get('/api/course/lab/students/full',{...data,page});
        if (!selected || !Array.isArray(selected.content)) throw Error('shape');
        entries.push(...selected.content);
      }
      const dates = await get('/api/courseLabTimes/date',{uid,courseId:course.id});
      for (const row of entries) {
        const safe = {};
        for (const key of ['id','course_student_lab_id','course_id','term_id','lab_name','course_name','teacher_name','address','dates','times']) {
          if (row[key] != null) safe[key] = row[key];
        }
        safe.dates = (dates && dates[row.id+'_'+row.select_week]) || safe.dates || '';
        rows.push(safe);
      }
    }
    if (localStorage.getItem('Authorization') !== authorization || student.user.username !== uid || student.currentTerm.id !== termId) {
      finish({state:'login'}); return;
    }
    finish({state:'ready',owner:uid,rows});
  })().catch(() => finish({state:localStorage.getItem('Authorization')?'error':'login'}));
})();
''';
