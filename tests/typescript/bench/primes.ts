function primes(n: number): number {
    let count = 0;
    for (let candidate = 2; candidate < n; candidate++) {
        let prime = true;
        for (let divisor = 2; divisor * divisor <= candidate; divisor++) {
            if (candidate % divisor === 0) { prime = false; break; }
        }
        if (prime) count = count + 1;
    }
    return count;
}
console.log(primes(50000));
