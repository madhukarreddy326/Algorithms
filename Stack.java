import java.util.EmptyStackException;

public class Stack {
    private int maxSize;
    private int[] stackArray;
    private int top;

    public Stack(int maxSize) {
        this.maxSize = maxSize;
        this.stackArray = new int[maxSize];
        this.top = -1;

    }

    // this helper method is to check if stack is full or not before push operation.
    public boolean isFull() {
        return maxSize - 1 == top;
    }

    // this helper method is to check if stack is empty or not before pop operation.
    public boolean isEmpty() {
        return top == -1;
    }

    // this helper method is to check the size of the statck
    public int size() {
        return top + 1;
    }

    // this method is used to push the given element into stack. Only condition we
    // need to check here is if stack already not empty thenn only push otherwise
    // error
    public void push(int element) {
        if (isFull()) {
            throw new RuntimeException("Stack is already full");
        }
        stackArray[++top] = element;
    }

    // this method is used to return the latest insetred element in stack and remove
    // from the stack
    public int pop() {
        if (isEmpty())
            throw new EmptyStackException();
        return stackArray[top--];
    }

    // this method is used to return the latest inserted element from the stack
    public int peek() {
        if (isEmpty()) {
            throw new EmptyStackException();
        } else
            return stackArray[top];
    }

    @Override
    public String toString() {
        // TODO Auto-generated method stub
        return stackArray.toString();
    }


}