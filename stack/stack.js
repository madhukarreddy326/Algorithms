var letters =[];//this is stack in java script
var word ="madamaa";
var rword = "";
console.log(word);

for(var i=0;i<word.length;i++)
    letters.push(word[i]);

for(var i=0;i<word.length;i++)    
    rword +=letters.pop();

if(word == rword)
    console.log(word +" is palindrom string");
else
    console.log(word +" is not palindrome string");
