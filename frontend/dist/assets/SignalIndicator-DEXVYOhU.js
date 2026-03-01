import{d as s,r as m,c as l,j as r,bZ as j,b_ as k,b$ as _}from"./index-DhkG1Nx9.js";/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const N=[["path",{d:"M5 12h14",key:"1ays0h"}],["path",{d:"m12 5 7 7-7 7",key:"xquz4c"}]],G=s("arrow-right",N);/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const v=[["path",{d:"M12 6v6l4 2",key:"mmk7yg"}],["circle",{cx:"12",cy:"12",r:"10",key:"1mglay"}]],P=s("clock",v);/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const w=[["path",{d:"M2 20h.01",key:"4haj6o"}],["path",{d:"M7 20v-4",key:"j294jx"}],["path",{d:"M12 20v-8",key:"i3yub9"}],["path",{d:"M17 20V8",key:"1tkaf5"}]],S=s("signal-high",w);/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const M=[["path",{d:"M2 20h.01",key:"4haj6o"}],["path",{d:"M7 20v-4",key:"j294jx"}]],A=s("signal-low",M);/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const C=[["path",{d:"M2 20h.01",key:"4haj6o"}],["path",{d:"M7 20v-4",key:"j294jx"}],["path",{d:"M12 20v-8",key:"i3yub9"}]],b=s("signal-medium",C);/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const R=[["path",{d:"M2 20h.01",key:"4haj6o"}]],B=s("signal-zero",R);/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const L=[["path",{d:"M2 20h.01",key:"4haj6o"}],["path",{d:"M7 20v-4",key:"j294jx"}],["path",{d:"M12 20v-8",key:"i3yub9"}],["path",{d:"M17 20V8",key:"1tkaf5"}],["path",{d:"M22 4v16",key:"sih9yq"}]],$=s("signal",L),E={excellent:"color(display-p3 0.00 1.00 0.00)",good:"color(display-p3 0.55 0.90 0.15)",fair:"color(display-p3 1.00 0.85 0.00)",weak:"color(display-p3 1.00 0.55 0.15)",poor:"color(display-p3 1.00 0.20 0.20)"},F={excellent:"#4ADE80",good:"#A3E635",fair:"#FACC15",weak:"#FB923C",poor:"#EF4444"};function d(e){return e>=-90?"excellent":e>=-100?"good":e>=-110?"fair":e>=-120?"weak":"poor"}function I(e,t,a,c=0){const n=_(t,e,a,c);return n?O(n.finalGrade):d(e)}function O(e){switch(e){case"excellent":return"excellent";case"good":return"good";case"fair":return"fair";case"poor":return"weak";case"critical":return"poor"}}function Z(e){switch(e){case"excellent":return"text-signal-excellent";case"good":return"text-signal-good";case"fair":return"text-signal-fair";case"weak":return"text-signal-poor";case"poor":return"text-signal-critical";default:return"text-fg-muted"}}function p(e,t,a=!0){return t?a?{backgroundColor:F[e],"--p3-color":E[e]}:{backgroundColor:"rgba(255, 255, 255, 0.25)"}:{backgroundColor:"rgba(255, 255, 255, 0.1)"}}function f(e,t=!0){return e&&t?"signal-bar-active":""}function J({rssi:e,className:t="w-4 h-4"}){const a=d(e),c=Z(a),n=l(c,t);switch(a){case"excellent":return r.jsx($,{className:n});case"good":return r.jsx(S,{className:n});case"fair":return r.jsx(b,{className:n});case"weak":return r.jsx(A,{className:n});case"poor":default:return r.jsx(B,{className:n})}}function D({rssi:e,snr:t,compact:a=!1,showValues:c=!0,radioConfig:n,nfPenalty:h=0,validated:i=!0}){const g=t!==void 0?I(e,t,n,h):d(e),x=4,u={excellent:4,good:3,fair:2,weak:1,poor:0}[g];return a?r.jsxs("div",{className:"flex items-center gap-1.5",children:[c&&r.jsx("span",{className:l("type-data-xs w-[32px] text-left",i?"text-fg-secondary":"text-fg-muted"),children:e}),r.jsx("div",{className:"flex items-center gap-[2px] h-3 w-[14px]",children:Array.from({length:x}).map((y,o)=>r.jsx("div",{className:l("w-[3px] h-full rounded-[1px] transition-colors",f(o<u,i)),style:p(g,o<u,i)},o))})]}):r.jsxs("div",{className:"flex items-center gap-2",children:[c&&r.jsxs("div",{className:"flex flex-col items-start w-[52px]",children:[r.jsxs("span",{className:l("type-data-xs leading-tight",i?"text-fg-secondary":"text-fg-muted"),children:[e," dBm"]}),t!==void 0&&r.jsxs("span",{className:"type-data-xs text-fg-muted leading-tight",children:[t.toFixed(1)," dB"]})]}),r.jsx("div",{className:"flex items-center gap-[2px] h-3.5 w-[14px]",children:Array.from({length:x}).map((y,o)=>r.jsx("div",{className:l("w-[3px] h-full rounded-[1px] transition-colors",f(o<u,i)),style:p(g,o<u,i)},o))})]})}const Q=m.memo(D);function T(e){const t=d(e);return t.charAt(0).toUpperCase()+t.slice(1)}function H(e){if(Array.isArray(e))return e;if(typeof e=="string"&&e.startsWith("["))try{const t=JSON.parse(e);return Array.isArray(t)?t:[]}catch{return[]}return[]}function q(e){const t=H(e.original_path),a=e.route??e.route_type;return j(a)?t.length===0:k(a)?t.length<=1:t.length===0}function U(e){return e.packet_origin==="tx_local"||e.packet_origin==="tx_forward"?!1:e._isZeroHop!=null?e._isZeroHop:q(e)}export{G as A,P as C,Q as S,$ as a,J as b,T as g,U as i};
