const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('lib/mod/physics_lab_bridge.dart', 'utf8').split("r'''")[1].split("'''")[0];

async function read({host='10.203.16.55:86',login=false,fail=false,switchAccount=false,officialDom=false}={}) {
  const calls=[];
  let authorization = 'fixture-authorization';
  const student={$options:{name:'studentCourse'},user:{username:'fixture-user'},currentTerm:{id:5},$children:[]};
  student.emitAjax = function(request) {
    assert.equal(request.type,'GET');
    assert.equal(request.data.uid,'fixture-user');
    if (request.path !== '/api/courseLabTimes/date') assert.equal(request.data.termId,5);
    calls.push({path:request.path,...request.data});
    if(fail) return request.error();
    if(request.path==='/api/courses/uid') return request.success([{id:10},{id:11}]);
    if(request.path==='/api/course/lab/students/full') {
      return request.success({content:[{id:request.data.courseId,course_student_lab_id:7,
        select_week:2,course_id:request.data.courseId,term_id:5,lab_name:'fixture lab',
        course_name:'fixture course',teacher_name:'fixture teacher',address:'fixture room',times:'10:00',
        token:'must-not-export',password:'must-not-export',student_name:'must-not-export'}]});
    }
    if(request.path==='/api/courseLabTimes/date') {
      if (switchAccount) authorization = 'fixture-different-session';
      return request.success({[request.data.courseId+'_2']:'2026-10-10'});
    }
    throw Error('unexpected endpoint');
  };
  const navbar = {$options:{name:'VueHead'},$children:[]};
  const parent = {$options:{name:'Index'},$children:[navbar,student]};
  navbar.$parent = parent; student.$parent = parent;
  const window={location:{host,pathname:login?'/lab-course/login':'/lab-course/studentCourse'}};
  const context={window,location:window.location,
    document:{querySelectorAll:()=>officialDom ? [{__vue__:navbar}, {}] : [{__vue__:student}]},
    localStorage:{getItem:()=>login?null:authorization},setTimeout};
  vm.runInNewContext(source,context,{timeout:1000});
  for(let i=0;i<1600;i++) {
    const result=window.__elychronPhysics;
    if(result && result.state!=='pending') return {result:JSON.parse(JSON.stringify(result)),calls};
    await new Promise(r=>setTimeout(r,5));
  }
  throw Error('bridge never completed');
}
(async()=>{
  const {result,calls}=await read();
  assert.equal(result.state,'ready');
  assert.equal(result.rows.length,2,'必须读取所有课程而非只取第一门');
  assert.equal(result.rows[1].course_id,11);
  assert.equal(result.rows[0].dates,'2026-10-10');
  assert.equal(calls.filter(c=>c.path==='/api/course/lab/students/full').length,2);
  assert.ok(!JSON.stringify(result).includes('must-not-export'),'仅输出课表字段，不输出凭据或个人档案');
  const blocked=await read({host:'unrelated.example'});
  assert.equal(blocked.result.state,'error'); assert.equal(blocked.calls.length,0);
  const login=await read({login:true});
  assert.equal(login.result.state,'login'); assert.equal(login.calls.length,0);
  assert.equal((await read({fail:true})).result.state,'error');
  assert.equal((await read({switchAccount:true})).result.state,'login','同步期间切换会话不能输出旧账号课表');
  const official=await read({officialDom:true});
  assert.equal(official.result.state,'ready','官网课表根元素没有 id，应通过带 id 的导航组件向上找到它');
  assert.equal(official.result.rows.length,2);
  console.log('PHYSICS_LAB_BRIDGE_TESTS PASSED');
})().catch(e=>{console.error(e);process.exit(1)});
