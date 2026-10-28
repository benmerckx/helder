// continue, do-while, labels, switch fallthrough
let s=0;for(let i=0;i<10;i++){if(i%2)continue;s+=i;}let j=0;while(j<5){j++;if(j==2)continue;s+=j;}console.log(s);
let i=0;do{i++}while(i<5);console.log(i);outer:for(let a=0;a<3;a++){for(let b=0;b<3;b++){if(b==1)continue outer;if(a==2)break outer;console.log(a,b)}}
function k(x:number|string){switch(x){case 1:return "one";case "a":case "b":return "ab";default:return "d";}}console.log(k(1),k("b"),k(3));
function f(n:number){let t=0;switch(n){case 1:t+=1;case 2:t+=2;case 3:t+=3;break;case 4:t+=4}return t}console.log(f(1),f(2),f(4),f(9));
function g(n:number){let r="";for(let i=0;i<n;i++){switch(i%3){case 0:continue;default:r+="d";case 1:r+=i;break}}return r}console.log(g(7));
