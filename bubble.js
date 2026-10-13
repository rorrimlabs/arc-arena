const ARRAY_SIZE = 100_000;

// Generate 100,000 random numbers
const originalArray = Array.from(
  { length: ARRAY_SIZE },
  () => Math.floor(Math.random() * 1_000_000)
);

// 1. Bubble Sort using optimized while
function bubbleSortWhile(arr) {
  let n = arr.length;

  while (n > 1) {
    let lastSwap = 0;

    for (let i = 0; i < n - 1; i++) {
      if (arr[i] > arr[i + 1]) {
        const temp = arr[i];
        arr[i] = arr[i + 1];
        arr[i + 1] = temp;

        lastSwap = i + 1;
      }
    }

    n = lastSwap;
  }

  return arr;
}

// 2. Bubble Sort using nested for loops
function bubbleSortFor(arr) {
  for (let i = 0; i < arr.length - 1; i++) {
    for (let j = 0; j < arr.length - i - 1; j++) {
      if (arr[j] > arr[j + 1]) {
        [arr[j], arr[j + 1]] = [arr[j + 1], arr[j]];
      }
    }
  }

  return arr;
}

// 3. JavaScript native Array.sort()
function nativeSort(arr) {
  return arr.sort((a, b) => a - b);
}

// Benchmark function
function benchmark(name, sortFunction, input) {
  // Each algorithm receives an independent copy
  const arr = [...input];

  console.log(`Starting ${name}...`);

  const start = performance.now();

  const result = sortFunction(arr);

  const end = performance.now();
  const duration = end - start;

  console.log(`${name}: ${(duration / 1000).toFixed(3)} seconds`);

  return {
    name,
    result,
    duration
  };
}

// Run benchmarks
const whileResult = benchmark(
  "Bubble Sort (optimized while)",
  bubbleSortWhile,
  originalArray
);

const forResult = benchmark(
  "Bubble Sort (nested for)",
  bubbleSortFor,
  originalArray
);

const nativeResult = benchmark(
  "JavaScript Native Sort",
  nativeSort,
  originalArray
);

// Verify all three produce identical results
const identical = whileResult.result.every(
  (value, index) =>
    value === forResult.result[index] &&
    value === nativeResult.result[index]
);

// Compare results
const results = [whileResult, forResult, nativeResult];

// Sort by execution time (fastest first)
results.sort((a, b) => a.duration - b.duration);

const fastest = results[0];

console.log("\n========== RESULTS ==========\n");

console.table(
  results.map((item, index) => ({
    Rank: index + 1,
    Algorithm: item.name,
    "Time (ms)": item.duration.toFixed(2),
    "Time (sec)": (item.duration / 1000).toFixed(3),
    "Slower Than Fastest": `${(item.duration / fastest.duration).toFixed(2)}x`
  }))
);

console.log("\nResults identical:", identical);
console.log("Fastest algorithm:", fastest.name);
console.log("Array size:", ARRAY_SIZE.toLocaleString());