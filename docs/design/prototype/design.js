/* Design tab: live compact-panel prototype and scale-to-fit for the wide mockups. */
(function(){
  'use strict';
  function pad(n){return (n<10?'0':'')+n}
  function hms(s){s=Math.max(0,s);var h=Math.floor(s/3600),m=Math.floor(s%3600/60),x=s%60;return h?h+':'+pad(m)+':'+pad(x):m+':'+pad(x)}
  function hm(s){s=Math.max(0,s);return Math.floor(s/3600)+':'+pad(Math.floor(s%3600/60))}
  function split(s){s=Math.max(0,s);var h=Math.floor(s/3600),m=Math.floor(s%3600/60),x=s%60;return [h?h+':'+pad(m):''+m,':'+pad(x)]}

  var ticks=[];
  [].forEach.call(document.querySelectorAll('[data-proto]'),function(root){
    var fig=root.parentNode,T,timer=null;
    function q(k){return fig.querySelector('[data-p="'+k+'"]')}
    try{T=JSON.parse(q('t').textContent)}catch(e){return}
    var idle0=root.getAttribute('data-proto')==='idle';
    var st={ws:'a',name:'Acme',issue:q('issue').textContent,total:7200,left:5050,
            mode:idle0?'idle':'work',paused:false,brk:0,picking:false,idleText:idle0?'0:15':'0:00'};

    function toast(msg){var el=q('toast');el.textContent=msg;clearTimeout(timer);timer=setTimeout(function(){el.textContent=''},4500)}
    /* Rhythm: 25 min focus, 5 min break, the last focus interval runs to the end of the block. */
    function eachBreak(fn){var tot=st.total/60;for(var t=25;t+5<tot;t+=30){if(fn(t,tot)===false)return}}
    function notches(){var h='';eachBreak(function(t,tot){h+='<i style="left:'+(t/tot*100).toFixed(2)+'%;width:'+(5/tot*100).toFixed(2)+'%"></i>'});q('notches').innerHTML=h}
    function nextBreak(){var e=(st.total-st.left)/60,n=0;eachBreak(function(t){if(t>e){n=Math.max(1,Math.round(t-e));return false}});return n}

    function render(){
      var idle=st.mode==='idle',pick=idle||st.picking,onBreak=st.mode==='break';
      q('run').hidden=pick;q('pick').hidden=!pick;
      q('back').hidden=idle;
      q('picktitle').textContent=idle?T.nothing:T.switchTo;
      fig.setAttribute('data-ws',st.ws);
      fig.classList.toggle('is-idle',idle);
      fig.classList.toggle('on-break',onBreak);
      fig.classList.toggle('is-paused',st.paused&&!idle);
      q('pill').textContent=idle?st.idleText:onBreak?hms(st.brk):st.paused?st.name+', '+T.paused:st.name+' '+(st.left<300?hms(st.left):hm(st.left));
      if(idle)return;
      q('ws').textContent=st.name;q('issue').textContent=st.issue;
      var d=split(onBreak?st.brk:st.left);q('dhm').textContent=d[0];q('dss').textContent=d[1];
      var nb=nextBreak();
      q('sub').textContent=st.paused?T.pausedSub:onBreak?T.breakSub.replace('%s',st.name):T.leftOf+' '+hm(st.total)+(nb?', '+T.breakIn.replace('%d',nb):'');
      q('fill').style.width=Math.round((st.total-st.left)/st.total*100)+'%';
      q('pauseL').textContent=st.paused?T.resume:T.pause;
      q('pauseI').setAttribute('href',st.paused?'#i-play':'#i-pause');
      q('breakL').textContent=onBreak?T.endBreak:T.breakBtn;
    }

    fig.addEventListener('click',function(e){
      var b=e.target.closest?e.target.closest('[data-a]'):null;
      if(!b||!fig.contains(b))return;
      var a=b.getAttribute('data-a');
      if(a==='pause'){st.paused=!st.paused}
      else if(a==='break'){if(st.mode==='break'){st.mode='work'}else{st.mode='break';st.brk=300;st.paused=false}}
      else if(a==='plus'){st.left+=900;st.total+=900;notches();toast(T.added)}
      else if(a==='switch'){st.picking=true}
      else if(a==='back'){st.picking=false}
      else if(a==='start'){
        st.ws=b.getAttribute('data-ws');st.name=b.getAttribute('data-name');st.issue=b.getAttribute('data-issue');
        st.total=st.left=(+b.getAttribute('data-min'))*60;st.mode='work';st.paused=false;st.picking=false;
        notches();toast(T.started.replace('%s',st.name));
      }
      else if(a==='focus'){toast(T.focused)}
      else if(a==='expand'){toast(T.expand)}
      else if(a==='custom'){toast(T.custom)}
      render();
    });

    ticks.push(function(){
      if(st.mode==='idle'||st.paused)return;
      if(st.mode==='break'){st.brk--;if(st.brk<=0)st.mode='work'}
      else{st.left--;if(st.left<=0){st.mode='idle';st.picking=false;st.idleText='0:00';toast(T.done)}}
      render();
    });
    render();
  });
  if(ticks.length)setInterval(function(){for(var i=0;i<ticks.length;i++)ticks[i]()},1000);

  /* Wide mockups keep their proportions: scale down to fit, and scroll sideways below 60%. */
  var boxes=[].slice.call(document.querySelectorAll('.fitbox'));
  function fit(box){
    var el=box.firstElementChild;if(!el)return;
    var nat=+el.getAttribute('data-fit'),w=box.clientWidth;if(!nat||!w)return;
    var r=w/nat,k=Math.max(.6,Math.min(1,r));
    box.classList.toggle('scroll',r<.6);
    if(el.__k!==k){el.__k=k;el.style.zoom=k}
  }
  if(window.ResizeObserver){
    var ro=new ResizeObserver(function(es){for(var i=0;i<es.length;i++)fit(es[i].target)});
    boxes.forEach(function(b){ro.observe(b)});
  }else{
    window.addEventListener('resize',function(){boxes.forEach(fit)});
  }
  boxes.forEach(fit);
})();

/* Jira review (hours stay editable before and after sending) and the Workspaces settings demo. */
(function(){
  'use strict';
  function pad(n){return (n<10?'0':'')+n}
  function f(m){return Math.floor(m/60)+':'+pad(m%60)}
  function hit(e,root){var b=e.target.closest?e.target.closest('[data-a]'):null;return b&&root.contains(b)?b:null}

  [].forEach.call(document.querySelectorAll('[data-review]'),function(root){
    var T;function g(k){return root.querySelector('[data-p="'+k+'"]')}
    try{T=JSON.parse(g('rt').textContent)}catch(e){return}
    var rows=[].map.call(root.querySelectorAll('[data-row]'),function(el){
      var d=+el.getAttribute('data-log');
      return {el:el,tracked:+el.getAttribute('data-tracked'),log:d,def:d,on:true,sent:null};
    });
    function wl(n){return (n===1?T.one:T.many).replace('%n',n)}
    function render(){
      var pend=0,pendSum=0,trk=0,chg=0,anySent=false;
      rows.forEach(function(r){
        function p(k){return r.el.querySelector('[data-p="'+k+'"]')}
        var cls='',txt;
        if(r.sent!==null){anySent=true;if(r.log!==r.sent){chg++;cls=' warn';txt=T.changed.replace('%s',f(r.sent))}else{cls=' ok';txt=T.inJira}}
        else if(r.on){pend++;pendSum+=r.log;trk+=r.tracked;cls=' warn';txt=T.toSend}
        else{txt=T.leftOut}
        p('val').textContent=f(r.log);
        p('chip').className='m-st'+cls;p('chip').textContent=txt;
        p('check').classList.toggle('on',r.on);
        r.el.classList.toggle('off',!r.on);
        r.el.classList.toggle('sent',r.sent!==null);
        r.el.classList.toggle('edited',r.log!==r.def);
      });
      var b=g('send'),label,off=false;
      if(pend&&chg)label=T.sendUpd.replace('%a',wl(pend)).replace('%b',chg);
      else if(pend)label=T.send.replace('%a',wl(pend)).replace('%s',f(pendSum));
      else if(chg)label=T.update.replace('%a',wl(chg));
      else{label=anySent?T.allIn:T.none;off=true}
      b.textContent=label;b.disabled=off;
      g('sum').textContent=pend?T.sum.replace('%t',f(trk)).replace('%s',f(pendSum)):'';
      var c=g('count');if(c){c.textContent=pend;c.hidden=!pend}
    }
    root.addEventListener('click',function(e){
      var b=hit(e,root);if(!b)return;
      var a=b.getAttribute('data-a'),el=b.closest('[data-row]'),r=null;
      rows.forEach(function(x){if(x.el===el)r=x});
      if(a==='minus'&&r){r.log=Math.max(15,r.log-15)}
      else if(a==='plus'&&r){r.log=Math.min(720,r.log+15)}
      else if(a==='toggle'&&r){if(r.sent===null)r.on=!r.on}
      else if(a==='send'){
        var fresh=false;
        rows.forEach(function(x){if(x.sent===null&&x.on)fresh=true;if(x.sent!==null||x.on)x.sent=x.log});
        g('status').textContent=fresh?T.sentMsg:T.updMsg;
      }
      render();
    });
    render();
  });

  [].forEach.call(document.querySelectorAll('[data-wsdemo]'),function(root){
    var D;function g(k){return root.querySelector('[data-p="'+k+'"]')}
    try{D=JSON.parse(g('wd').textContent)}catch(e){return}
    var list=D.ws.slice(),sel=0,colors=['a','b','c','d','e','f'];
    function esc(s){return String(s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
    function render(focusName,fromInput){
      var w=list[sel],n=g('name');
      g('list').innerHTML=list.map(function(x,i){
        return '<button class="m-wsitem'+(i===sel?' on':'')+'" data-a="pick" data-i="'+i+'" data-ws="'+x.c+'"><i class="m-dot"></i><span>'+esc(x.name||D.unnamed)+'</span></button>';
      }).join('');
      if(!fromInput)n.value=w.name;
      [].forEach.call(root.querySelectorAll('[data-a="color"]'),function(b){b.classList.toggle('on',b.getAttribute('data-ws')===w.c)});
      g('block').textContent=w.block;g('rhythm').textContent=w.rhythm;
      g('folders').innerHTML=w.folders.length?w.folders.map(function(p){return '<span class="m-code">'+esc(p)+'</span>'}).join(''):'<span class="m-sub">'+esc(D.noFolders)+'</span>';
      g('jira').textContent=w.jira||D.none;g('cal').textContent=w.cal||D.none;g('round').textContent=w.round||'15 min';
      var sw=g('breaks');sw.classList.toggle('on',!!w.breaks);sw.setAttribute('aria-checked',w.breaks?'true':'false');
      g('qs').textContent=D.qs.replace('%n',sel+1);
      if(focusName){n.focus();n.select()}
    }
    root.addEventListener('click',function(e){
      var b=hit(e,root);if(!b)return;
      var a=b.getAttribute('data-a');
      if(a==='pick'){sel=+b.getAttribute('data-i');render()}
      else if(a==='color'){list[sel].c=b.getAttribute('data-ws');render()}
      else if(a==='breaks'){list[sel].breaks=!list[sel].breaks;render()}
      else if(a==='add'){
        if(list.length>=8)return;
        var used=list.map(function(x){return x.c});
        var free=colors.filter(function(c){return used.indexOf(c)<0});
        list.push({name:D.newName,c:free[0]||'d',block:'1 h',rhythm:D.ws[0].rhythm,folders:[],jira:'',cal:'',round:'15 min',breaks:true});
        sel=list.length-1;render(true);
      }
      else if(a==='remove'){if(list.length>1){list.splice(sel,1);sel=Math.max(0,sel-1);render()}}
    });
    g('name').addEventListener('input',function(){list[sel].name=this.value;render(false,true)});
    render();
  });
})();
