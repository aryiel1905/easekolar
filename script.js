// Simulate user login status
let isLoggedIn = false;

function handleApply() {
  if (!isLoggedIn) {
    window.location.href = "scholarship.html";
  } else {
    window.location.href = "login-signup.html";
  }
}

// Fake login function
function loginUser(event) {
  event.preventDefault();
  isLoggedIn = true;
  alert("Login successful! Redirecting to scholarships...");
  window.location.href = "scholarship.html";
}
