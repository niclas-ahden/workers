use crate::error_template::{AppError, ErrorTemplate};
use leptos::*;
use leptos_meta::*;
use leptos_router::*;
use leptos_workers::worker;
use serde::{Serialize, Deserialize};

#[component]
pub fn App() -> impl IntoView {
    // Provides context that manages stylesheets, titles, meta tags, etc.
    provide_meta_context();

    view! {


        // injects a stylesheet into the document <head>
        // id=leptos means cargo-leptos will hot-reload this stylesheet
        <Stylesheet id="leptos" href="/pkg/workers.css"/>

        // sets the document title
        <Title text="Welcome to Leptos"/>

        // content for this welcome page
        <Router fallback=|| {
            let mut outside_errors = Errors::default();
            outside_errors.insert_with_default_key(AppError::NotFound);
            view! {
                <ErrorTemplate outside_errors/>
            }
            .into_view()
        }>
            <main>
                <Routes>
                    <Route path="" view=HomePage/>
                </Routes>
            </main>
        </Router>
    }
}

#[component]
fn HomePage() -> impl IntoView {
    let (count, set_count) = create_signal(0);
    let on_click = move |_| {
        // Create a dummy value (5_i32) that we want to share with the worker. Box it up and get a
        // raw pointer to it. The pointer is a `usize`, so we can pass it to the worker without
        // Seralize/Deserialize.
        let pointer = Box::into_raw(Box::new(5_i32)) as usize;
        spawn_local(async move {
            let WorkerResponse(r) = work(WorkerRequest { pointer }).await.expect("Worker");
            logging::log!("main: {}", r);
            set_count.update(|count| *count += 1);
        });
    };

    view! {
        <h1>"Welcome to Leptos!"</h1>
        <button on:click=on_click>"Click Me: " {count}</button>
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct WorkerResponse(i32);

#[derive(Clone, Serialize, Deserialize)]
pub struct WorkerRequest {
    pointer: usize,
}

#[worker(Work)]
pub async fn work(req: WorkerRequest) -> WorkerResponse {
    let num = unsafe { *Box::from_raw(req.pointer as *mut i32) };

    logging::log!("Worker got: {}", num);

    WorkerResponse(num)
}
