var Stack = function(){
    this.storage= {};
    this.count=0;

    this.push = function(value){
        console.log("value is ");
       this.storage[this.count]= value;
       this.count++;
    }
    this.pop = function(){
        if(this.count ==0)
        {
            return undefined;
        }
        this.count--;
        var result = this.storage[this.count];
        delete this.storage[this.count];
        return result;


    }
    this.size =function()
    {
        return this.count;
    }
    this.peek = function()    {

        return this.storage[this.count-1];
    }
}

    var myStack = new Stack();
    myStack.pop();
    myStack.push(10);
    myStack.push(20);
    
    console.log(myStack.pop());
    console.log(myStack.peek());
    myStack.push(30);
    console.log(myStack.peek());
    myStack.push(30);
    myStack.push(30);
    myStack.push(30);
    console.log(myStack.size());

