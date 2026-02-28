import{d as p,r as e,cl as f,j as m,cm as A}from"./index-C1ZF7cAz.js";import{A as h}from"./index-DCNWD5GU.js";/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const y=[["path",{d:"M6 18.5a3.5 3.5 0 1 0 7 0c0-1.57.92-2.52 2.04-3.46",key:"1qngmn"}],["path",{d:"M6 8.5c0-.75.13-1.47.36-2.14",key:"b06bma"}],["path",{d:"M8.8 3.15A6.5 6.5 0 0 1 19 8.5c0 1.63-.44 2.81-1.09 3.76",key:"g10hsz"}],["path",{d:"M12.5 6A2.5 2.5 0 0 1 15 8.5M10 13a2 2 0 0 0 1.82-1.18",key:"ygzou7"}],["line",{x1:"2",x2:"22",y1:"2",y2:"22",key:"a6p6uj"}]],E=p("ear-off",y),j=e.memo(function({value:t,format:a,prefix:s,suffix:i,className:r,priority:c="medium"}){const[n,u]=e.useState(!1),[d,o]=e.useState(t);e.useEffect(()=>f(()=>{u(!0),o(0)},c),[c]),e.useEffect(()=>{n&&o(t)},[n,t]);const l=`${s??""}${t.toLocaleString(void 0,a)}${i??""}`;return n?m.jsx(h,{className:`${r??""} overflow-hidden`,format:a,prefix:s,suffix:i,transition:A.numberTicker,children:d}):m.jsx("span",{className:r,children:l})});export{j as A,E};
