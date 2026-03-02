import{d as i,r as m,c as l,j as r,c6 as j,c7 as _,c8 as k}from"./index-CeMilrX4.js";/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const N=[["path",{d:"M5 12h14",key:"1ays0h"}],["path",{d:"m12 5 7 7-7 7",key:"xquz4c"}]],z=i("arrow-right",N);/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const w=[["path",{d:"M2 20h.01",key:"4haj6o"}],["path",{d:"M7 20v-4",key:"j294jx"}],["path",{d:"M12 20v-8",key:"i3yub9"}],["path",{d:"M17 20V8",key:"1tkaf5"}]],v=i("signal-high",w);/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const S=[["path",{d:"M2 20h.01",key:"4haj6o"}],["path",{d:"M7 20v-4",key:"j294jx"}]],M=i("signal-low",S);/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const A=[["path",{d:"M2 20h.01",key:"4haj6o"}],["path",{d:"M7 20v-4",key:"j294jx"}],["path",{d:"M12 20v-8",key:"i3yub9"}]],C=i("signal-medium",A);/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const b=[["path",{d:"M2 20h.01",key:"4haj6o"}]],R=i("signal-zero",b);/**
 * @license lucide-react v0.559.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const B=[["path",{d:"M2 20h.01",key:"4haj6o"}],["path",{d:"M7 20v-4",key:"j294jx"}],["path",{d:"M12 20v-8",key:"i3yub9"}],["path",{d:"M17 20V8",key:"1tkaf5"}],["path",{d:"M22 4v16",key:"sih9yq"}]],L=i("signal",B),E={excellent:"color(display-p3 0.00 1.00 0.00)",good:"color(display-p3 0.55 0.90 0.15)",fair:"color(display-p3 1.00 0.85 0.00)",weak:"color(display-p3 1.00 0.55 0.15)",poor:"color(display-p3 1.00 0.20 0.20)"},F={excellent:"#4ADE80",good:"#A3E635",fair:"#FACC15",weak:"#FB923C",poor:"#EF4444"};function d(e){return e>=-90?"excellent":e>=-100?"good":e>=-110?"fair":e>=-120?"weak":"poor"}function I(e,t,a,s=0){const n=k(t,e,a,s);return n?O(n.finalGrade):d(e)}function O(e){switch(e){case"excellent":return"excellent";case"good":return"good";case"fair":return"fair";case"poor":return"weak";case"critical":return"poor"}}function $(e){switch(e){case"excellent":return"text-signal-excellent";case"good":return"text-signal-good";case"fair":return"text-signal-fair";case"weak":return"text-signal-poor";case"poor":return"text-signal-critical";default:return"text-fg-muted"}}function p(e,t,a=!0){return t?a?{backgroundColor:F[e],"--p3-color":E[e]}:{backgroundColor:"rgba(255, 255, 255, 0.25)"}:{backgroundColor:"rgba(255, 255, 255, 0.1)"}}function f(e,t=!0){return e&&t?"signal-bar-active":""}function G({rssi:e,className:t="w-4 h-4"}){const a=d(e),s=$(a),n=l(s,t);switch(a){case"excellent":return r.jsx(L,{className:n});case"good":return r.jsx(v,{className:n});case"fair":return r.jsx(C,{className:n});case"weak":return r.jsx(M,{className:n});case"poor":default:return r.jsx(R,{className:n})}}function D({rssi:e,snr:t,compact:a=!1,showValues:s=!0,radioConfig:n,nfPenalty:h=0,validated:c=!0}){const g=t!==void 0?I(e,t,n,h):d(e),x=4,u={excellent:4,good:3,fair:2,weak:1,poor:0}[g];return a?r.jsxs("div",{className:"flex items-center gap-1.5",children:[s&&r.jsx("span",{className:l("type-data-xs w-[32px] text-left",c?"text-fg-secondary":"text-fg-muted"),children:e}),r.jsx("div",{className:"flex items-center gap-[2px] h-3 w-[14px]",children:Array.from({length:x}).map((y,o)=>r.jsx("div",{className:l("w-[3px] h-full rounded-[1px] transition-colors",f(o<u,c)),style:p(g,o<u,c)},o))})]}):r.jsxs("div",{className:"flex items-center gap-2",children:[s&&r.jsxs("div",{className:"flex flex-col items-start w-[52px]",children:[r.jsxs("span",{className:l("type-data-xs leading-tight",c?"text-fg-secondary":"text-fg-muted"),children:[e," dBm"]}),t!==void 0&&r.jsxs("span",{className:"type-data-xs text-fg-muted leading-tight",children:[t.toFixed(1)," dB"]})]}),r.jsx("div",{className:"flex items-center gap-[2px] h-3.5 w-[14px]",children:Array.from({length:x}).map((y,o)=>r.jsx("div",{className:l("w-[3px] h-full rounded-[1px] transition-colors",f(o<u,c)),style:p(g,o<u,c)},o))})]})}const P=m.memo(D);function J(e){const t=d(e);return t.charAt(0).toUpperCase()+t.slice(1)}function H(e){if(Array.isArray(e))return e;if(typeof e=="string"&&e.startsWith("["))try{const t=JSON.parse(e);return Array.isArray(t)?t:[]}catch{return[]}return[]}function Z(e){const t=H(e.original_path),a=e.route??e.route_type;return j(a)?t.length===0:_(a)?t.length<=1:t.length===0}function Q(e){return e.packet_origin==="tx_local"||e.packet_origin==="tx_forward"?!1:e._isZeroHop!=null?e._isZeroHop:Z(e)}export{z as A,P as S,L as a,G as b,J as g,Q as i};
